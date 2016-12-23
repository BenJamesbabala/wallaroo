use "buffered"
use "collections"
use "net"
use "time"
use "wallaroo/boundary"
use "wallaroo/fail"
use "wallaroo/invariant"
use "wallaroo/metrics"
use "wallaroo/routing"
use "wallaroo/tcp-sink"
use "wallaroo/topology"

use @pony_asio_event_create[AsioEventID](owner: AsioEventNotify, fd: U32,
  flags: U32, nsec: U64, noisy: Bool)
use @pony_asio_event_fd[U32](event: AsioEventID)
use @pony_asio_event_unsubscribe[None](event: AsioEventID)
use @pony_asio_event_resubscribe[None](event: AsioEventID, flags: U32)
use @pony_asio_event_destroy[None](event: AsioEventID)

actor TCPSource is Producer
  """
  # TCPSource

  ## Future work
  * Switch to requesting credits via promise
  """
  // Credit Flow
  let _routes: MapIs[CreditFlowConsumer, Route] = _routes.create()
  let _route_builder: RouteBuilder val
  let _outgoing_boundaries: Map[String, OutgoingBoundary] val
  let _tcp_sinks: Array[TCPSink] val
  // Determines if we can still process credits from consumers
  var _unregistered: Bool = false
  var _max_route_credits: ISize = 1_024

  let _metrics_reporter: MetricsReporter

  // TCP
  let _listen: TCPSourceListener
  let _notify: TCPSourceNotify
  var _next_size: USize
  let _max_size: USize
  var _connect_count: U32
  var _fd: U32 = -1
  var _expect: USize = 0
  var _connected: Bool = false
  var _closed: Bool = false
  var _event: AsioEventID = AsioEvent.none()
  var _read_buf: Array[U8] iso
  var _shutdown_peer: Bool = false
  var _readable: Bool = false
  var _read_len: USize = 0
  var _reading: Bool = false
  var _shutdown: Bool = false
  var _muted: Bool =
    ifdef "backpressure" then
      true
    else
      false
    end
  var _expect_read_buf: Reader = Reader

  // Origin (Resilience)
  var _seq_id: SeqId = 1 // 0 is reserved for "not seen yet"

  new _accept(listen: TCPSourceListener, notify: TCPSourceNotify iso,
    routes: Array[CreditFlowConsumerStep] val, route_builder: RouteBuilder val,
    outgoing_boundaries: Map[String, OutgoingBoundary] val,
    tcp_sinks: Array[TCPSink] val,
    fd: U32, default_target: (CreditFlowConsumerStep | None) = None,
    forward_route_builder: (RouteBuilder val | None) = None,
    init_size: USize = 64, max_size: USize = 16384,
    metrics_reporter: MetricsReporter iso)
  =>
    """
    A new connection accepted on a server.
    """
    _metrics_reporter = consume metrics_reporter
    _listen = listen
    _notify = consume notify
    _notify.set_origin(this)
    _connect_count = 0
    _fd = fd
    ifdef linux then
      _event = @pony_asio_event_create(this, fd,
        AsioEvent.read_write_oneshot(), 0, true)
    else
      _event = @pony_asio_event_create(this, fd,
        AsioEvent.read_write(), 0, true)
    end
    _connected = true
    _read_buf = recover Array[U8].undefined(init_size) end
    _next_size = init_size
    _max_size = 65_536

    _route_builder = route_builder
    _outgoing_boundaries = outgoing_boundaries
    _tcp_sinks = tcp_sinks

    //TODO: either only accept when we are done recovering or don't start
    //listening until we are done recovering
    _notify.accepted(this)

    let handler: TCPSourceRouteCallbackHandler ref =
      TCPSourceRouteCallbackHandler

    for consumer in routes.values() do
      _routes(consumer) =
        _route_builder(this, consumer, handler, _metrics_reporter)
    end

    for (worker, boundary) in _outgoing_boundaries.pairs() do
      _routes(boundary) =
        _route_builder(this, boundary, handler, _metrics_reporter)
    end

    match default_target
    | let r: CreditFlowConsumerStep =>
      match forward_route_builder
      | let frb: RouteBuilder val =>
        _routes(r) = frb(this, r, handler, _metrics_reporter)
      end
    end

    for r in _routes.values() do
      // TODO: this is a hack, we shouldn't be calling application events
      // directly. route lifecycle needs to be broken out better from
      // application lifecycle
      r.application_created()
    end

    for r in _routes.values() do
      r.application_initialized(_max_route_credits, "TCPSource")
    end

  //////////////
  // ORIGIN (resilience)
  fun ref _x_resilience_routes(): Routes =>
    // TODO: we don't really need this
    // Because we dont actually do any resilience work
    Routes

  // Override these for TCPSource as we are currently
  // not resilient.
  fun ref _flush(low_watermark: U64) =>
    None

  be log_flushed(low_watermark: SeqId) =>
    None

  fun ref _bookkeeping(o_route_id: RouteId, o_seq_id: SeqId,
    i_origin: Producer, i_route_id: RouteId, i_seq_id: SeqId)
  =>
    None

  be update_watermark(route_id: RouteId, seq_id: SeqId) =>
    ifdef "trace" then
      @printf[I32]("TCPSource received update_watermark\n".cstring())
    end

  fun ref _update_watermark(route_id: RouteId, seq_id: SeqId) =>
    None

  be dispose() =>
    """
    - Close the connection gracefully.
    """
    close()

  //
  // CREDIT FLOW
  fun ref recoup_credits(credits: ISize) =>
    // We don't hand credits upstream from a source, so we don't need to
    // recoup them
    None

  be receive_credits(credits: ISize, from: CreditFlowConsumer) =>
    ifdef debug then
      Invariant(_routes.contains(from))
    end

    if _unregistered then
      ifdef "credit_trace" then
        @printf[I32]("Unregistered source returning credits unused\n".cstring())
      end
      from.return_credits(credits)
    else
      try
        let route = _routes(from)
        route.receive_credits(credits)
      end
    end

  fun ref route_to(c: CreditFlowConsumer): (Route | None) =>
    try
      _routes(c)
    else
      None
    end

  fun ref next_sequence_id(): U64 =>
    _seq_id = _seq_id + 1

  //
  // TCP
  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    """
    Handle socket events.
    """
    if event isnt _event then
      if AsioEvent.writeable(flags) then
        // A connection has completed.
        var fd = @pony_asio_event_fd(event)
        _connect_count = _connect_count - 1

        if not _connected and not _closed then
          // We don't have a connection yet.
          if @pony_os_connected[Bool](fd) then
            // The connection was successful, make it ours.
            _fd = fd
            _event = event
            _connected = true

            _notify.connected(this)
          else
            // The connection failed, unsubscribe the event and close.
            @pony_asio_event_unsubscribe(event)
            @pony_os_socket_close[None](fd)
            _notify_connecting()
          end
        else
          // We're already connected, unsubscribe the event and close.
          @pony_asio_event_unsubscribe(event)
          @pony_os_socket_close[None](fd)
        end
      else
        // It's not our event.
        if AsioEvent.disposable(flags) then
          // It's disposable, so dispose of it.
          @pony_asio_event_destroy(event)
        end
      end
    else
      if AsioEvent.readable(flags) then
        _readable = true
        _pending_reads()
      end

      if AsioEvent.disposable(flags) then
        @pony_asio_event_destroy(event)
        _event = AsioEvent.none()
      end

      _try_shutdown()
    end
    _resubscribe_event()

  fun ref _notify_connecting() =>
    """
    Inform the notifier that we're connecting.
    """
    if _connect_count > 0 then
      _notify.connecting(this, _connect_count)
    else
      _notify.connect_failed(this)
      _hard_close()
    end

  fun ref close() =>
    """
    Attempt to perform a graceful shutdown. Don't accept new writes. If the
    connection isn't muted then we won't finish closing until we get a zero
    length read.  If the connection is muted, perform a hard close and
    shut down immediately.
    """
    if _muted then
      _hard_close()
    else
      _close()
    end

  fun ref _close() =>
    _closed = true
    _try_shutdown()

  fun ref _try_shutdown() =>
    """
    If we have closed and we have no remaining writes or pending connections,
    then shutdown.
    """
    if not _closed then
      return
    end

    if
      not _shutdown and
      (_connect_count == 0)
    then
      _shutdown = true

      if _connected then
        @pony_os_socket_shutdown[None](_fd)
      else
        _shutdown_peer = true
      end
    end

    if _connected and _shutdown and _shutdown_peer then
      _hard_close()
    else
      if not _unregistered then
        _dispose_routes()
      end
    end

  fun ref _hard_close() =>
    """
    When an error happens, do a non-graceful close.
    """
    if not _connected then
      return
    end

    _connected = false
    _closed = true
    _shutdown = true
    _shutdown_peer = true

    // Unsubscribe immediately and drop all pending writes.
    @pony_asio_event_unsubscribe(_event)
    _readable = false

    @pony_os_socket_close[None](_fd)
    _fd = -1

    _notify.closed(this)

    _listen._conn_closed()
    if not _unregistered then
      _dispose_routes()
    end
    _unregistered = true

  fun ref _dispose_routes() =>
    for r in _routes.values() do
      r.dispose()
    end
    _muted = true
    _unregistered = true

  fun ref _pending_reads() =>
    """
    Unless this connection is currently muted, read while data is available,
    guessing the next packet length as we go. If we read 4 kb of data, send
    ourself a resume message and stop reading, to avoid starving other actors.
    """
    try
      var sum: USize = 0
      _reading = true

      while _readable and not _shutdown_peer do
        if _muted then
          _reading = false
          return
        end

        while (_expect_read_buf.size() > 0) and
          (_expect_read_buf.size() >= _expect)
        do
          let block_size = if _expect != 0 then
            _expect
          else
            _expect_read_buf.size()
          end

          let out = _expect_read_buf.block(block_size)
          let carry_on = _notify.received(this, consume out)
          // We might have become muted while handling the
          // last batch of data
          if _muted then
            _reading = false
            return
          end
          if not carry_on then
            _read_again()
            _reading = false
            return
          end

          sum = sum + block_size

          if sum >= _max_size then
            // If we've read _max_size, yield and read again later.
            _read_again()
            _reading = false
            return
          end
        end

        // Read as much data as possible.
        _read_buf_size(sum)
        let len = @pony_os_recv[USize](
          _event,
          _read_buf.cpointer().usize() + _read_len,
          _read_buf.size() - _read_len) ?

        match len
        | 0 =>
          // Would block, try again later.
          _readable = false
          _resubscribe_event()
          _reading = false
          return
        | _next_size =>
          // Increase the read buffer size.
          _next_size = _max_size.min(_next_size * 2)
        end

         _read_len = _read_len + len

        if _expect != 0 then
          let data = _read_buf = recover Array[U8] end
          data.truncate(_read_len)
          _read_len = 0

          _expect_read_buf.append(consume data)

          while (_expect_read_buf.size() > 0) and
            (_expect_read_buf.size() >= _expect)
          do
            let block_size = if _expect != 0 then
              _expect
            else
              _expect_read_buf.size()
            end

            let out = _expect_read_buf.block(block_size)
            let osize = block_size

            let carry_on = _notify.received(this, consume out)
            // We might have become muted while handling the
            // last batch of data
            if _muted then
              _reading = false
              return
            end
            if not carry_on then
              _read_again()
              _reading = false
              return
            end

            sum = sum + osize

            if sum >= _max_size then
              // If we've read _max_size, yield and read again later.
              _read_again()
              _reading = false
              return
            end
          end
        else
          let data = _read_buf = recover Array[U8] end
          data.truncate(_read_len)
          let dsize = _read_len
          _read_len = 0

          let carry_on = _notify.received(this, consume data)
          // We might have become muted while handling the
          // last batch of data
          if _muted then
            _reading = false
            return
          end
          if not carry_on then
            _read_again()
            _reading = false
            return
          end

          sum = sum + dsize

          if sum >= _max_size then
            // If we've read _max_size, yield and read again later.
            _read_again()
            _reading = false
            return
          end
        end
      end
    else
      // The socket has been closed from the other side.
      _shutdown_peer = true
      close()
    end

    _reading = false

  be _read_again() =>
    """
    Resume reading.
    """

    _pending_reads()

  fun ref _read_buf_size(less: USize) =>
    """
    Resize the read buffer.
    """

    let size = if (_next_size + less) <= _max_size then
      _next_size
    else
      _next_size.min(_max_size - less)
    end

    _read_buf.undefined(size)

  fun ref _mute() =>
    ifdef "credit_trace" then
      @printf[I32]("MUTE\n".cstring())
    end
    _muted = true

  fun ref _unmute() =>
    ifdef "credit_trace" then
      @printf[I32]("UNMUTE\n".cstring())
    end
    _muted = false
    if not _reading then
      _pending_reads()
    end

  be unmute() =>
    _unmute()

  fun ref is_muted(): Bool =>
    _muted

  fun ref expect(qty: USize = 0) =>
    """
    A `received` call on the notifier must contain exactly `qty` bytes. If
    `qty` is zero, the call can contain any amount of data.
    """
    // TODO: verify that removal of "in_sent" check is harmless
    _expect = _notify.expect(this, qty)

  fun ref _resubscribe_event() =>
    ifdef linux then
      let flags = if not _readable then
        AsioEvent.read() or AsioEvent.oneshot()
      else
        return
      end

      @pony_asio_event_resubscribe(_event, flags)
    end

class TCPSourceRouteCallbackHandler is RouteCallbackHandler
  let _registered_routes: SetIs[RouteLogic tag] = _registered_routes.create()
  var _muted: ISize = 0
  let _timers: Timers = Timers

  fun ref register(producer: Producer ref, r: RouteLogic tag) =>
    ifdef debug then
      Invariant(not _registered_routes.contains(r))
    end

    match producer
    | let s: TCPSource ref =>
      _registered_routes.set(r)
      ifdef "backpressure" then
        _try_mute(s)
      end
    else
      Fail()
    end

  fun shutdown(producer: Producer ref) =>
    match producer
    | let p: TCPSource ref =>
      p._hard_close()
    else
      Fail()
    end

  fun ref credits_initialized(producer: Producer ref, r: RouteLogic tag) =>
    ifdef debug then
      Invariant(_registered_routes.contains(r))
    end

    match producer
    | let s: TCPSource ref =>
      _try_unmute(s)
    end

  fun ref credits_replenished(producer: Producer ref) =>
    ifdef debug then
      Invariant(_muted > 0)
    end

    match producer
    | let s: TCPSource ref =>
      _try_unmute(s)
      ifdef "credit_trace" then
        @printf[I32]("Credits_replenished. Now _muted=%llu\n".cstring(),
          _muted)
      end
    else
      Fail()
    end

  fun ref credits_exhausted(producer: Producer ref) =>
    match producer
    | let s: TCPSource ref =>
      _try_mute(s)
      ifdef "credit_trace" then
        @printf[I32]("Credits_exhausted. Now _muted=%llu\n".cstring(),
          _muted)
      end
    else
      Fail()
    end

  fun ref _try_mute(s: TCPSource ref) =>
    if _muted == 0 then
      s._mute()
    end
    _muted = _muted + 1

  fun ref _try_unmute(s: TCPSource ref) =>
    _muted = _muted - 1
    if _muted == 0 then
      s._unmute()
    end

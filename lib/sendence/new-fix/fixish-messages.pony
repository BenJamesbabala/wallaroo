use "buffered"
use "../fix"
use "../bytes"

primitive FixTypes
  fun order(): U8 => 1
  fun nbbo(): U8 => 2

primitive SideTypes
  fun buy(): U8 => 1
  fun sell(): U8 => 2

primitive FixishMsgEncoder
  fun order(side: Side val, account: U32, order_id: String, symbol: String, 
    order_qty: F64, price: F64, transact_time: String, 
    wb: Writer = Writer): Array[ByteSeq] val =>
      //Header
      let msgs_size: USize = 1 + 1 + 4 + order_id.size() 
        + symbol.size() + 8 + 8 + transact_time.size()
      wb.u32_be(msgs_size.u32()) 
      //Fields
      wb.u8(FixTypes.order())
      match side
      | Buy => wb.u8(SideTypes.buy())
      | Sell => wb.u8(SideTypes.sell())
      end
      wb.u32_be(account)
      wb.write(order_id.array())
      wb.write(symbol.array())
      wb.f64_be(order_qty)
      wb.f64_be(price)
      wb.write(transact_time.array())
      wb.done()

  fun nbbo(symbol: String, transact_time: String, bid_px: F64, offer_px: F64, 
    wb: Writer = Writer): Array[ByteSeq] val =>
      //Header
      let msgs_size: USize = 1 + symbol.size() + transact_time.size() + 8 + 8
      wb.u32_be(msgs_size.u32()) 
      //Fields
      wb.u8(FixTypes.nbbo())
      wb.write(symbol)
      wb.write(transact_time)
      wb.f64_be(bid_px)
      wb.f64_be(offer_px)
      wb.done()

primitive FixishMsgDecoder
  fun apply(data: Array[U8] val): FixMessage val ? =>
    match data(0)
    | FixTypes.order() => order(data)
    | FixTypes.nbbo() => nbbo(data)
    else
      OtherFixMessage
    end

  fun order(data: Array[U8] val): FixOrderMessage val ? =>
    // 0 -  1b - FixType (U8)
    // 1 -  1b - side (U8)
    // 2 -  4b - account (U32)
    // 6 -  6b - order id (String)
    //12 -  4b - symbol (String)
    //16 -  8b - order qty (F64)
    //24 -  8b - price (F64)
    //32 - 21b - transact_time (String)
    // --
    // 52 bytes

    let side = match data(1)
    | SideTypes.buy() => Buy
    | SideTypes.sell() => Sell
    else
      error
    end
    let account = Bytes.to_u32(data(2), data(3), data(4), data(5))
    let order_id = _trim_string(data, 6, 6)
    let symbol = _trim_string(data, 12, 4)
    let order_qty: F64 = 6.66
    let price: F64 = 66.6
    let transact_time = _trim_string(data, 32, 21)
    FixOrderMessage(side, account, order_id, symbol, order_qty, price, 
      transact_time)  

  fun nbbo(data: Array[U8] val): FixNbboMessage val =>
    // 0 -  1b - FixType (U8)
    // 1 -  4b - symbol (String)
    // 5 - 21b - transact_time (String)
    //26 -  8b - bid_px (F64)
    //34 -  8b - offer_px (F64)
    // --
    // 42 bytes
    var idx: USize = 1
    var cur_size: USize = 0

    let symbol = _trim_string(data, 1, 4)
    let transact_time = _trim_string(data, 5, 21)
    let bid_px: F64 = 666
    let offer_px: F64 = 666

    FixNbboMessage(symbol, transact_time, bid_px, offer_px)  

  fun _size_for(data: Array[U8] val, idx: USize): USize ? =>
    Bytes.to_u32(data(idx), data(idx + 1), data(idx + 2), 
      data(idx + 3)).usize()

  fun _trim_string(data: Array[U8] val, idx: USize, size: USize): String =>
    String.from_array(data.trim(idx, idx + size))
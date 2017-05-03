use "wallaroo/fail"

trait WActor
  fun ref receive(sender: WActorId, payload: Any val, h: WActorHelper)
    """
    Called when receiving a message from another WActor
    """
  fun ref process(data: Any val, h: WActorHelper)
    """
    Called when receiving data from a Wallaroo pipeline
    """

class EmptyWActor is WActor
  fun ref receive(sender: WActorId, payload: Any val, h: WActorHelper) =>
    Fail()
  fun ref process(data: Any val, h: WActorHelper) => Fail()

interface val WActorBuilder
  fun apply(id: U128, wh: WActorHelper): WActor

trait WActorHelper
  fun ref send_to(target: WActorId, data: Any val)
  fun ref send_to_role(role: String, data: Any val)
  fun ref register_as_role(role: String)
  fun ref create_actor(builder: WActorBuilder)
  fun ref destroy_actor(id: WActorId)
  fun known_actors(): Array[WActorId] val
  fun ref set_timer(duration: U128, callback: {()},
    is_repeating: Bool = false): WActorTimer
  fun ref cancel_timer(t: WActorTimer)

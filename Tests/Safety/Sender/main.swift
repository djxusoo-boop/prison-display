import AppKit
import Network
setbuf(stdout,nil)
var failures=0
func check(_ ok:Bool,_ name:String){print(ok ? "PASS:" : "FAIL:",name);if !ok{failures+=1}}
func pump(_ condition:()->Bool,timeout:Double=10)->Bool{let until=Date().addingTimeInterval(timeout);while !condition() && Date()<until{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};return condition()}
let sender=SenderEngine();sender.screenPermission={true};sender.graphicsLoadReader={100}
sender.pointer.trusted={false};sender.keyboard.trusted={false};sender.pointer.post={_ in check(false,"no OS pointer event may be posted")};sender.keyboard.post={_ in check(false,"no OS key event may be posted")}
let clientQueue=DispatchQueue(label:"Safety.receiver"),decoder=H264Decoder()
var client:Peer?,pixels=0,stopped=false,protected=false,error:String?
decoder.onPixel={_ in DispatchQueue.main.async{pixels+=1}}
sender.onStatus={if $0.contains("saturando el sistema de color"){protected=true};print("STATUS:",$0)}
sender.onLink={link in guard let link=link else{return};DispatchQueue.main.async{do{let peer=Peer(NWConnection(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:link.port)!,using:try networkParameters(key:link.key)),queue:clientQueue);client=peer;peer.onReady={peer.send(.hello,Wire.hello(role:"receiver"))};peer.onEnd={_ in DispatchQueue.main.async{stopped=true}};peer.onPacket={kind,data in if kind == .video{do{let frame=try VideoFrame(data);try decoder.decode(frame);var ack=Data();ack.u64(frame.sequence);ack.u64(frame.timestamp);ack.u64(0);peer.send(.ack,ack)}catch let e{DispatchQueue.main.async{error=String(describing:e)}}}};peer.start()}catch let e{error=String(describing:e)}}}
do{try sender.start(key:newPairingKey(),options:StreamOptions(extend:true,width:1280,height:720,fps:30,bitrate:6_000_000))}catch let e{error=String(describing:e)}
check(pump({pixels>=3 || error != nil}) && pixels>=3 && error == nil,"real TLS and codec start with a simulated virtual display")

var routedMouse: [CGEventType] = [], routedKeys: [CGEventType] = []
sender.pointer.trusted={true}; sender.keyboard.trusted={true}
sender.pointer.post={ event in DispatchQueue.main.async { routedMouse.append(event.type) } }
sender.keyboard.post={ event in DispatchQueue.main.async { routedKeys.append(event.type) } }
sender.queue.sync { sender.pointer.displayID = CGMainDisplayID() }
sender.setInputSharing(mouse: false, keyboard: true); sender.queue.sync {}
client?.send(.pointer, PointerMessage(action: .leftDown,x:0.5,y:0.5).serialize())
client?.send(.keyboard, KeyboardMessage(action: .down,keyCode:0).serialize())
check(pump({routedKeys.contains(.keyDown)}) && routedMouse.isEmpty, "sender blocks remote mouse while allowing keyboard")
sender.setInputSharing(mouse: false, keyboard: true); sender.queue.sync {}
RunLoop.current.run(until:Date().addingTimeInterval(0.02))
check(!routedKeys.contains(.keyUp), "changing mouse sharing does not release an independent held keyboard key")
sender.setInputSharing(mouse: true, keyboard: false); sender.queue.sync {}
client?.send(.keyboard, KeyboardMessage(action: .down,keyCode:1).serialize())
client?.send(.pointer, PointerMessage(action: .leftDown,x:0.5,y:0.5).serialize())
check(pump({routedMouse.contains(.leftMouseDown) && routedKeys.contains(.keyUp)}) && routedKeys.filter({$0 == .keyDown}).count == 1, "sender releases keyboard and still accepts mouse independently")
sender.setInputSharing(mouse: false, keyboard: false); sender.queue.sync {}
check(pump({routedMouse.contains(.leftMouseUp)}), "sender releases held button when mouse sharing is disabled")
sender.pointer.trusted={false};sender.keyboard.trusted={false}
Capture.stopNeverResponds=true
let occupied=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
sender.queue.async{occupied.signal();_=release.wait(timeout:.now()+12)}
check(occupied.wait(timeout:.now()+1) == .success,"input queue deliberately occupied")
var ticks=0
let heartbeat=Timer.scheduledTimer(withTimeInterval:0.05,repeats:true){_ in ticks+=1}
check(pump({ADMockActiveDisplays()==0},timeout:8),"overload retires virtual display while input queue remains blocked")
check(ticks>10,"interface stays responsive during protection")
release.signal()
check(pump({protected && stopped}),"overload reason and disconnect are delivered after queue recovers")
check(ADMockActiveDisplays()==0,"missing capture-stop callback cannot retain the display")
Capture.stopNeverResponds=false;heartbeat.invalidate();decoder.stop();client?.end();sender.stop()
let exiting=SenderEngine();exiting.pointer.trusted={false};exiting.keyboard.trusted={false}
let blocked=DispatchSemaphore(value:0),unblock=DispatchSemaphore(value:0)
exiting.queue.async{blocked.signal();_=unblock.wait(timeout:.now()+3)}
_=blocked.wait(timeout:.now()+1);let began=Date();exiting.releasePointerBeforeExit()
check(Date().timeIntervalSince(began)<0.75,"exit is bounded even with a blocked input queue");unblock.signal()
print("RESULT",failures,"failures; injected faults, no real virtual display or OS input posted")
exit(failures==0 ? 0 : 1)

MultiPass provides a simple setup for getting apps talking to each other in person or online.

Supported connectivity is:
Bonjour (aka MultiPeer)
SharePlay (aka GroupActivities)

To establish a MultiPass configuration, pass in a multipeerName (to use Bonjour) and/or a MultiPass.Activity type, and the message types you want to send between your app(s). An example:
```
    let multipass = MultiPass(configuration: .init(multipeerName: "mpexample", activityType: MyAppGroupActivity.self, messageTypes: myAppMessages))
```

The MultipeerName is just a string, but it must correspond with a Bonjour configuration added to your project's Info.plist (or App settings). An example with a multipeerName: "mpexample" follows:
```
	<key>NSBonjourServices</key>
	<array>
		<string>_mpexample._tcp</string>
		<string>_mpexample._udp</string>
	</array>
```

The activityType must conform to a MultiPass.Activity (which is also GroupActivity):
```
struct MyAppGroupActivity: MultiPass.Activity {
    static let activityIdentifier = "com.appsyoucanmake.MultiPassExample"
    
    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "Our Activity"
        meta.subtitle = "Send a message to your friends"
        return meta
    }
}
```
By configuring a MultiPass.Activity, MultiPass will be listening for SharePlay sessions of that type to start.

Note: Your app is responsible for starting and joining SharePlay sessions, but MultiPeer will also be watching for sessions and connect messaging once they are joined.

MultiPassMessage requires a message to be Codable, Sendable, and provide a static multiPassMessageType. MessageTypes 6000-6100 are reserved for MultiPass. An example:
```
struct TextMessage: MultiPassMessage {
    static var multiPassMessageType: Int { 2 }
    
    let text: String
}
```

//
//  SillonWidgetLiveActivity.swift
//  SillonWidget
//
//  Created by Thomas Kohler on 27.06.2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SillonWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct SillonWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SillonWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension SillonWidgetAttributes {
    fileprivate static var preview: SillonWidgetAttributes {
        SillonWidgetAttributes(name: "World")
    }
}

extension SillonWidgetAttributes.ContentState {
    fileprivate static var smiley: SillonWidgetAttributes.ContentState {
        SillonWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: SillonWidgetAttributes.ContentState {
         SillonWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: SillonWidgetAttributes.preview) {
   SillonWidgetLiveActivity()
} contentStates: {
    SillonWidgetAttributes.ContentState.smiley
    SillonWidgetAttributes.ContentState.starEyes
}

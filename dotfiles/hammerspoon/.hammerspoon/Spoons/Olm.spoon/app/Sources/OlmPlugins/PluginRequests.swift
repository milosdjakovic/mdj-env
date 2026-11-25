// What a plugin may ask of Olm, docs/DESIGN-APP-PLUGINS.md What a plugin may ask. A plugin says what
// to open and Olm decides how, so no request carries a program, a path or an argument: whatever Olm
// starts runs outside the plugin's sandbox and with none of its limits.

import Foundation
import OlmBridge
import OlmKit

public enum PluginRequests {
  /// Every request there is, each named in a manifest's `needs` before it is answered.
  public static let known: Set<String> = ["open", "copy", "notify"]

  /// A link to open, in the browser or profile Olm named by that id, or in Olm's own choice.
  public struct Link: Sendable, Equatable {
    public let url: URL
    public let browser: String?
  }

  /// The link an `open` asks for, or why it is refused. Only http and https with a host: a file can
  /// be a program, and another scheme acts in the application that owns it.
  public static func link(_ params: JSON) -> Result<Link, RunningPlugin.Refusal> {
    guard params["app"].isNull, params["args"].isNull else {
      return .failure(.init(-32602, "open takes a browser Olm listed, never an application or arguments"))
    }
    guard let text = params["url"].string, let url = URL(string: text), let host = url.host, !host.isEmpty,
      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
      return .failure(.init(-32602, "open needs an http or https link"))
    }
    if params["browser"].isNull { return .success(Link(url: url, browser: nil)) }
    guard let browser = params["browser"].string else {
      return .failure(.init(-32602, "open's browser is an id Olm listed"))
    }
    return .success(Link(url: url, browser: browser))
  }
}

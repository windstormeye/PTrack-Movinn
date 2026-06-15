//
//  StravaDefine.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/15.
//

import Foundation

struct StravaDefine {
    let ClientID: String = "258270"
    let ClientSecret: String = "baae1044ab75cb0922f55d88b6bb1299c9701071"
    let AuthorizationCallbackDomain: String = "pj.studio"
    let RedirectURI: String = "ptrack://pj.studio/strava/oauth"
    let CallbackScheme: String = "ptrack"
    let AuthorizationScope: String = "read,activity:read_all"
    let AuthorizationURL: String = "https://www.strava.com/oauth/mobile/authorize"
    let TokenURL: String = "https://www.strava.com/oauth/token"
    let APIBaseURL: String = "https://www.strava.com/api/v3"
}

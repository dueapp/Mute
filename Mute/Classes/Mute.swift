//
//  Mute.swift
//  Mute
//
//  Created by Akram Hussein on 08/09/2017.
//

import Foundation
import AudioToolbox
import UIKit

@objcMembers
public class Mute: NSObject {

    public typealias MuteNotificationCompletion = ((_ mute: Bool) -> Void)

    // MARK: Properties

    /// Shared instance
    public static let shared = Mute()

    /// Sound ID for mute sound
    private let soundUrl = Mute.muteSoundUrl

    /// Should notify every second or only when changes?
    /// True will notify every second of the state, false only when it changes
    public var alwaysNotify = true

    /// Notification handler to be triggered when mute status changes
    /// Triggered every second if alwaysNotify=true, otherwise only when it switches state
    public var notify: MuteNotificationCompletion?

    /// Currently playing? used when returning from the background (if went to background and foreground really quickly)
    public private(set) var isPlaying = false

    /// Current mute state
    public private(set) var isMute = false

    /// Internal flag tracking whether a check has been scheduled to take place
    private var checkIsScheduled = false

    /// State of detection - paused when in background
    public var isPaused = false {
        didSet {
            if !self.isPaused && oldValue && !self.isPlaying {
                self.schedulePlaySoundIfNeeded()
            }
        }
    }
    
    /// Whether checks are scheduled to take place at `checkInterval`
    public var scheduled = false {
        didSet {
            if scheduled {
                schedulePlaySoundIfNeeded()
            }
        }
    }
    
    /// How frequently to check (seconds), minimum = 0.5
    public var checkInterval = 1.0 {
        didSet {
            if self.checkInterval < 0.5 {
                print("MUTE: checkInterval cannot be less than 0.5s, setting to 0.5")
                self.checkInterval = 0.5
            }
        }
    }

    /// Silent sound (0.5 sec)
    private var soundId: SystemSoundID = 0

    /// Time difference between start and finish of mute sound
    private var interval: TimeInterval = 0

    // MARK: Resources

    /// Library bundle
    private static var bundle: Bundle {
        if let path = Bundle(for: Mute.self).path(forResource: "Mute", ofType: "bundle"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        let spmBundleName = "Mute_Mute"

        let candidates = [
            // Bundle should be present here when the package is linked into an App.
            Bundle.main.resourceURL,

            // Bundle should be present here when the package is linked into a framework.
            Bundle(for: Mute.self).resourceURL
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(spmBundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }

        fatalError("Mute.bundle not found")
    }

    /// Mute sound url path
    private static var muteSoundUrl: URL {
        guard let muteSoundUrl = Mute.bundle.url(forResource: "mute", withExtension: "aiff") else {
            fatalError("mute.aiff not found")
        }
        return muteSoundUrl
    }

    // MARK: Init

    /// private init
    private override init() {
        super.init()

        self.soundId = 1

        if AudioServicesCreateSystemSoundID(self.soundUrl as CFURL, &self.soundId) == kAudioServicesNoError {
            var yes: UInt32 = 1
            AudioServicesSetProperty(kAudioServicesPropertyIsUISound,
                                     UInt32(MemoryLayout.size(ofValue: self.soundId)),
                                     &self.soundId,
                                     UInt32(MemoryLayout.size(ofValue: yes)),
                                     &yes)
        } else {
            print("Failed to setup sound player")
            self.soundId = 0
        }

        // Notifications
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(Mute.didEnterBackground(_:)),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(Mute.willEnterForeground(_:)),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }

    deinit {
        if self.soundId != 0 {
            AudioServicesRemoveSystemSoundCompletion(self.soundId)
            AudioServicesDisposeSystemSoundID(self.soundId)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Notification Handlers

    /// Selector called when app enters background
    @objc private func didEnterBackground(_ sender: Any) {
        self.isPaused = true
    }

    /// Selector called when app will enter foreground
    @objc private func willEnterForeground(_ sender: Any) {
        self.isPaused = false
    }

    // MARK: Methods

    /// Starts a mute check outside the `checkInterval`
    public func check(completion: MuteNotificationCompletion?) {
        self.playSound(completion: completion)
    }

    /// Schedules mute sound to be played at `checkInterval`
    private func schedulePlaySoundIfNeeded() {
        /// Don't start a schedule if we're not asked to
        /// Don't schedule a new one if we already have one queued
        guard scheduled, self.checkIsScheduled == false else {
            return
        }

        self.checkIsScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + self.checkInterval) {
            self.checkIsScheduled = false

            /// Don't play if we're paused
            if self.isPaused {
                return
            }

            self.playSound()
        }
    }

    /// If not paused, playes mute sound
    private func playSound(completion: MuteNotificationCompletion? = nil) {
        if !self.isPaused && !self.isPlaying {
            self.interval = Date.timeIntervalSinceReferenceDate
            self.isPlaying = true
            AudioServicesPlaySystemSoundWithCompletion(self.soundId) { [weak self] in
                self?.soundFinishedPlaying(completion: completion)
            }
        }
    }

    /// Called when AudioService finished playing sound
    private func soundFinishedPlaying(completion: MuteNotificationCompletion? = nil) {
        self.isPlaying = false

        let elapsed = Date.timeIntervalSinceReferenceDate - self.interval
        let isMute = elapsed < 0.1

        if self.isMute != isMute || self.alwaysNotify {
            self.isMute = isMute
            DispatchQueue.main.async {
                self.notify?(isMute)
                completion?(isMute)
            }
        }
        self.schedulePlaySoundIfNeeded()
    }
}

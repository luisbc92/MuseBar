//
//  WindowController.swift
//  Muse
//
//  Created by Marco Albera on 21/11/16.
//  Copyright © 2016 Edge Apps. All rights reserved.
//

import Cocoa
import Carbon.HIToolbox
import MediaPlayer
import LoginServiceKit

@available(OSX 10.12.2, *)
fileprivate extension NSTouchBarItem.Identifier {
    static let controlStripButton = NSTouchBarItem.Identifier(
        rawValue: "\(Bundle.main.bundleIdentifier!).TouchBarItem.controlStripButton"
    )
}

@available(OSX 10.12.2, *)
class WindowController: NSWindowController, NSWindowDelegate, SliderDelegate {
    
    // MARK: App delegate getter
    
    let delegate = NSApplication.shared.delegate as? AppDelegate
    
    // MARK: Helpers

    let manager: PlayersManager = PlayersManager.shared
    var helper: PlayerHelper    = PlayersManager.shared.designatedHelper
    let nowPlayingInfoCenter    = MPNowPlayingInfoCenter.default()
    let remoteCommandCenter     = MPRemoteCommandCenter.shared()
    
    // MARK: Key monitor
    var eventMonitor: Any?
    
    // MARK: Runtime properties
    
    var song                           = Song()
    var nowPlayingInfo: [String : Any] = [:]
    var autoCloseTimeout: TimeInterval = 1.5
    
    // MARK: Timers
    
    var songTrackingTimer = Timer()
    
    // MARK: Keys
    
    let kSong = "song"
    // Constant for setting menu title length
    let kMenuItemMaximumLength = 20
    // Constant for setting song title maximum length in TouchBar button
    let songTitleMaximumLength = 14
    // Constant for TouchBar slider bounds
    let xSliderBoundsThreshold: CGFloat = 25
    
    // iTunes notification fields
    // TODO: move this in a better place
    let iTunesNotificationTrackName          = "Name"
    let iTunesNotificationPlayerState        = "Player State"
    let iTunesNotificationPlayerStatePlaying = "Playing"

    // MARK: Outlets
    
    weak var songArtworkTitleButton:     NSCustomizableButton?
    weak var songProgressSlider:         Slider?
    weak var controlsSegmentedView:      NSSegmentedControl?
    weak var likeButton:                 NSButton?
    weak var soundPopoverButton:         NSPopoverTouchBarItem?
    weak var soundSlider:                NSSliderTouchBarItem?
    weak var shuffleRepeatSegmentedView: NSSegmentedControl?
    weak var launchAtLoginButton:        NSSegmentedControl?
    weak var quitButton:                 NSButton?
    
    // MARK: Vars
    
    let controlStripItem = NSControlStripTouchBarItem(identifier: .controlStripButton)
    
    var controlStripButton: NSCustomizableButton? {
        set {
            controlStripItem.view = newValue!
        }
        get {
            return controlStripItem.view as? NSCustomizableButton
        }
    }
    
    // Hardcoded control strip item size
    // frame.size returns a wrong value at cold start
    let controlStripButtonSize = NSMakeSize(58.0, 58.0)
    
    var didPresentAsSystemModal = false
    
    var isSliding = false
    
    // Returns whether the UI is in play state
    var isUIPlaying = false
    
    // If an event is sent from TouchBar control strip button should not be refreshed
    // Set to true at event sent, reset to false after notification is received
    var eventSentFromApp = false
    
    // MARK: Actions
    
    @objc func controlsSegmentedViewClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            helper.previousTrack()
        case 1:
            helper.togglePlayPause()
        case 2:
            helper.nextTrack()
        default:
            return
        }
    }
    
    @objc func shuffleRepeatSegmentedViewClicked(_ sender: NSSegmentedControl) {
        let selectedSegment = sender.selectedSegment
        
        switch selectedSegment {
        case 0:
            // Toggle shuffling
            shuffleButtonClicked(sender)
        case 1:
            // Toggle repeating
            repeatButtonClicked(sender)
        default:
            return
        }
    }
    
    @objc func shuffleButtonClicked(_ sender: Any) {
        switch sender {
        case let segmented as NSSegmentedControl:
            helper.shuffling = segmented.isSelected(forSegment: segmented.selectedSegment)
        case _ as NSButton:
            helper.shuffling = !helper.shuffling
        default:
            break
        }
    }
    
    @objc func repeatButtonClicked(_ sender: Any) {
        switch sender {
        case let segmented as NSSegmentedControl:
            helper.repeating = segmented.isSelected(forSegment: segmented.selectedSegment)
        case _ as NSButton:
            helper.repeating = !helper.repeating
        default:
            break
        }
    }
    
    @objc func soundSliderValueChanged(_ sender: NSSliderTouchBarItem) {
        // Set the volume on the player
        helper.volume = sender.slider.integerValue
        
        updateSoundPopoverButton(for: helper.volume)
    }
    
    @objc func songArtworkTitleButtonClicked(_ sender: NSButton) {
        // Jump to player when the artwork on the TouchBar is tapped
        showPlayer()
    }
    
    @objc func likeButtonClicked(_ sender: NSButton) {
        // Reverse like on current track if supported
        if var helper = helper as? LikablePlayerHelper {
            helper.toggleLiked()
        }
    }
    
    @objc func launchAtLoginButtonClicked(_ sender: NSSegmentedControl) {
        if LoginServiceKit.isExistLoginItems() {
            LoginServiceKit.removeLoginItems()
        } else {
            LoginServiceKit.addLoginItems()
        }
        updateLaunchAtLoginButton()
    }
    
    @objc func quitButtonClicked(_ sender: NSButton) {
        // Quit the app
        NSApplication.shared.terminate(self)
    }
    
    // MARK: SliderDelegate implementation
    // Handles touch events from TouchBar song progres slider
    
    var wasPlaying = false
    
    /**
     Handles 'touchesBegan' events from the slider
     */
    func didTouchesBegan() {
        // Save player state
        wasPlaying = helper.isPlaying
        
        // Handle single touch events
        helper.scrub(to: songProgressSlider?.doubleValue, touching: false)
    }
    
    /**
     Handles 'touchesMoved' events from the slider
     */
    func didTouchesMoved() {
        // Pause player
        // so it doesn't mess with sliding
        if helper.isPlaying { helper.pause() }
        
        // Set new position to the player
        helper.scrub(to: songProgressSlider?.doubleValue, touching: true)
    }
    
    /**
     Handles 'touchesEnded' events from the slider
     */
    func didTouchesEnd() {
        // Finalize and disable large knob
        helper.scrub(to: songProgressSlider?.doubleValue, touching: false)
        
        // Resume playing if needed
        if wasPlaying { helper.play() }
    }
    
    /**
     Handles 'touchesCancelled' events form the slider
     */
    func didTouchesCancel() {
        // Same action as touch ended
        didTouchesEnd()
    }
      
    func showPlayer() {
        let player = NSRunningApplication.runningApplications(
            withBundleIdentifier: type(of: helper).BundleIdentifier
            )[0]
        
        // Takes to the player window
        player.activate(options: .activateIgnoringOtherApps)
    }
    
    // MARK: Player loading
    
    func setPlayerHelper(to id: PlayerID) {
        // Set the new player
        helper = manager.get(id)
        
        // Register again the callbacks
        registerCallbacks()
        
        // Load the new song
        handleNewSong()
        
        // Update timing
        trackSongProgress()
        
        // Authorize Spotify if needed
        if id == .spotify {
            SpotifyHelper.shared.authorizeIfNeeded()
        }
    }
    
    // MARK: Callbacks
    
    /**
     Callback for PlayerHelper's togglePlayPause()
     */
    func playPauseHandler() {
        if !helper.doesSendPlayPauseNotification {
            handlePlayPause()
            trackSongProgress()
        }
    }
    
    /**
     Callback for PlayerHelper's nextTrack() and previousTrack()
     */
    func trackChangedHandler(next: Bool) {
        updateSongProgressSlider(with: 0)
        
        updateNowPlayingInfo()
    }
    
    /**
     Callback for PlayerHelper's goTo(Bool, Double?)
     */
    func timeChangedHandler(touching: Bool, time: Double) {
        if let cell = songProgressSlider?.cell as? SliderCell {
            // If we are sliding, show time near TouchBar slider knob
            cell.knobImage   = touching ? nil : .playhead
            cell.hasTimeInfo = touching
            cell.timeInfo    = time.secondsToMMSSString as NSString
        }
        
        updateSongProgressSlider(with: time)
        
        // Set 'isSliding' after a short delay
        // This prevents timer from resuming too early
        // after scrubbing, thus resetting the slider position
        DispatchQueue.main.run(after: 5) { self.isSliding = touching }
    }
    
    func registerCallbacks() {
        PlayerNotification.observe { [weak self] event in
            guard let strongSelf = self else { return }
            
            strongSelf.eventSentFromApp = true
            
            switch event {
            case .play, .pause:
                strongSelf.playPauseHandler()
            case .next:
                strongSelf.trackChangedHandler(next: true)
            case .previous:
                strongSelf.trackChangedHandler(next: false)
            case .scrub(let touching, let time):
                strongSelf.timeChangedHandler(touching: touching, time: time)
            case .shuffling(let enabled):
                strongSelf.setShuffleRepeatSegmentedView(shuffleSelected: enabled)
            case .repeating(let enabled):
                strongSelf.setShuffleRepeatSegmentedView(repeatSelected: enabled)
            case .like(let liked):
                // Update like button on TouchBar
                strongSelf.updateLikeButton(newValue: liked)
            }
            
            // Reset event sent variable for events that don't send a notification
            switch event {
            case .scrub(_, _), .shuffling(_), .repeating(_), .like(_):
                strongSelf.eventSentFromApp = false
            default: break
            }
        }
    }
    
    // MARK: TouchBar injection
    
    /**
     Appends a system-wide button in NSTouchBar's control strip
     */
    @objc func injectControlStripButton() {
        prepareControlStripButton()
        
        DFRSystemModalShowsCloseBoxWhenFrontMost(true)
        
        controlStripItem.isPresentInControlStrip = true
    }
    
    func prepareControlStripButton() {
        controlStripButton = NSCustomizableButton(
            title: musicSymbol.string,
            target: self,
            action: #selector(triggerPlayPause),
            hasRoundedLeadingImage: false
        )
        
        controlStripButton?.textColor     = NSColor.white.withAlphaComponent(0.8)
        controlStripButton?.font = NSFont(name: "SF Pro Text", size: 18.0)
        
        controlStripButton?.imagePosition = .imageOverlaps
        controlStripButton?.isBordered    = false
        controlStripButton?.imageScaling  = .scaleNone
        
        controlStripButton?.addGestureRecognizer(controlStripButtonPressureGestureRecognizer)
        controlStripButton?.addGestureRecognizer(controlStripButtonPanGestureRecognizer)
        
        updateControlStripButton()
    }
    
    func updateControlStripButton() {
        if song.isValid && helper.isPlaying {
            controlStripButton?.attributedTitle = pauseSymbol
        } else if song.isValid && !helper.isPlaying {
            controlStripButton?.attributedTitle = playSymbol
        } else {
            controlStripButton?.attributedTitle = musicSymbol
        }
    }
    
    var pauseSymbol: NSAttributedString {
        return NSAttributedString(string: "􀊆", attributes: [.baselineOffset: 1.5])
    }
    
    var playSymbol: NSAttributedString {
        return NSAttributedString(string: "􀊄", attributes: [.baselineOffset: 1.5])
    }
    
    var musicSymbol: NSAttributedString {
        return NSAttributedString(string: "􀑪", attributes: [.baselineOffset: 1.5])
    }
    
    /**
     Recognizes long press gesture on the control strip button.
     We use this to toggle play/pause from the system bar.
     */
    var controlStripButtonPressureGestureRecognizer: NSPressGestureRecognizer {
        let recognizer = NSPressGestureRecognizer()
        
        recognizer.target = self
        recognizer.action = #selector(controlStripButtonPressureGestureHandler(_:))
        
        recognizer.minimumPressDuration = 0.25
        recognizer.allowedTouchTypes    = .direct  // Very important
        
        return recognizer
    }
    
    /**
     Recognizes pan (aka touch drag) gestures on the control strip button.
     We use this to reveal the designated NSTouchBar.
     */
    var controlStripButtonPanGestureRecognizer: NSPanGestureRecognizer {
        let recognizer = NSPanGestureRecognizer()
        
        recognizer.target = self
        recognizer.action = #selector(controlStripButtonPanGestureHandler(_:))
        
        recognizer.allowedTouchTypes = .direct
        
        return recognizer
    }
    
    @objc func controlStripButtonPressureGestureHandler(_ sender: NSGestureRecognizer?) {
        guard let recognizer = sender else { return }
        
        switch recognizer.state {
        case .began:
            presentModalTouchBar()
        default:
            break
        }
    }
    
    @objc func controlStripButtonPanGestureHandler(_ sender: NSGestureRecognizer?) {
        guard let recognizer = sender as? NSPanGestureRecognizer else { return }
        
        switch recognizer.state {
        case .began:
            // Reverse translation check (natural scroll)
            if recognizer.translation(in: controlStripButton).x < 0 {
                helper.previousTrack()
            } else {
                helper.nextTrack()
            }
        default:
            break
        }
    }
    
    /**
     Reveals the designated NSTouchBar when control strip button @objc is pressed
    */
    @objc func triggerPlayPause() {
        helper.togglePlayPause()
    }
    
    /**
     Reveals the designated NSTouchBar when control strip button @objc is pressed
     */
    @objc func presentModalTouchBar() {
        updatePopoverButtonForControlStrip()
        
        touchBar?.presentAsSystemModal(for: controlStripItem)
        
        didPresentAsSystemModal = true
    }
    
    // MARK: UI preparation
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        // Initialize AEManager for URL handling
        initEventManager()
        
        // Initialize notification watcher
        initNotificationWatchers()
        
        // Set custom window attributes
        prepareWindow()
        
        // Register callbacks for PlayerHelper
        registerCallbacks()
        
        // Prepare system-wide controls
        prepareRemoteCommandCenter()
        
        // Append system-wide button in Control Strip
        injectControlStripButton()
        
        // Show window
        window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.hide(self)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Try switching to another helper is song is blank
        // (that means previous player has been closed)
        // Or if helper is no longer available
        // Also this loads song at cold start
        if song == Song() || !helper.isAvailable {
            setPlayerHelper(to: manager.designatedHelperID)
        }
        
        // Sync progress slider if song is not playing
        if !helper.isPlaying { syncSongProgressSlider() }
        
        // Sync the sound slider and button
        prepareSoundSlider()
        
        // Sync shuffling and repeating segmented control
        prepareShuffleRepeatSegmentedView()
        
        // Sync Launch at Login status
        prepareLaunchAtLoginButton()
        
        // Get song details
        prepareSong()
        
        // Update control strip button title
        updateControlStripButton()
        
        toggleControlStripButton()
        
        // Invalidate TouchBar to make it reload
        // This ensures it's always correctly displayed
        // Only if system modal bar has been used
        if didPresentAsSystemModal {
            touchBar                = nil
            didPresentAsSystemModal = false
        }
        
        // Update like button when window becomes key
        updateLikeButtonColdStart()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        // Make sure we reset sent event variable
        eventSentFromApp = false
    }
    
    func toggleControlStripButton() {
        controlStripButton?.animator().isHidden  = false
        controlStripItem.isPresentInControlStrip = true
        DispatchQueue.main.run(after: 200) {
            self.toggleControlStripButton()
        }
    }
    
    func prepareWindow() {
        guard let window = self.window else { return }
        
        window.titleVisibility = NSWindow.TitleVisibility.hidden;
        window.titlebarAppearsTransparent = true
        window.styleMask.update(with: NSWindow.StyleMask.fullSizeContentView)
        
        // Set fixed window position (at the center of the screen)
        window.center()
        window.isMovable = false
        
        // Show on every workspace
        window.collectionBehavior = .transient
        
        // Hide after losing focus
        window.hidesOnDeactivate = true
        
        // Set the delegate
        window.delegate = self
        
        window.makeFirstResponder(self)
    }
    
    func prepareSong() {
        song = helper.song
        
        updateAfterNotification()
        
        trackSongProgress()
        
        self.helper.updatePlayer()
        DispatchQueue.main.run(after: 500) {
            self.helper.updatePlayer()
        }
    }
    
    func prepareButtons() {
        controlsSegmentedView?.target       = self
        controlsSegmentedView?.segmentCount = 3
        controlsSegmentedView?.segmentStyle = .separated
        controlsSegmentedView?.trackingMode = .momentary
        controlsSegmentedView?.action       = #selector(controlsSegmentedViewClicked(_:))
        
        controlsSegmentedView?.setImage(.previous, forSegment: 0)
        controlsSegmentedView?.setImage(.play, forSegment: 1)
        controlsSegmentedView?.setImage(.next, forSegment: 2)
        
        (0..<(controlsSegmentedView?.segmentCount)!).forEach {
            controlsSegmentedView?.setWidth(45.0, forSegment: $0)
        }
    }
    
    func prepareSongProgressSlider() {
        songProgressSlider?.delegate = self
        songProgressSlider?.minValue = 0.0
        songProgressSlider?.maxValue = 1.0
        
        if songProgressSlider?.doubleValue == 0.0 {
            songProgressSlider?.doubleValue = helper.playbackPosition / song.duration
        }
    }
    
    func prepareSongArtworkTitleButton() {
        songArtworkTitleButton?.target        = self
        songArtworkTitleButton?.bezelStyle    = .rounded
        songArtworkTitleButton?.alignment     = .center
        songArtworkTitleButton?.fontSize      = 16.0
        songArtworkTitleButton?.imagePosition = .imageLeading
        songArtworkTitleButton?.action        = #selector(songArtworkTitleButtonClicked(_:))
        
        songArtworkTitleButton?.hasRoundedLeadingImage = true
        
        songArtworkTitleButton?.addGestureRecognizer(songArtworkTitleButtonPanGestureRecognizer)
    }
    
    /**
     Recognizes pan (aka touch drag) gestures on the song artwork+title button.
     We use this to toggle song information on the button
     */
    @objc var songArtworkTitleButtonPanGestureRecognizer: NSGestureRecognizer {
        let recognizer = NSPanGestureRecognizer()
        
        recognizer.target = self
        recognizer.action = #selector(songArtworkTitleButtonPanGestureHandler(_:))
        
        recognizer.allowedTouchTypes = .direct
        
        return recognizer
    }
    
    @objc func songArtworkTitleButtonPanGestureHandler(_ recognizer: NSPanGestureRecognizer) {
        var count = 0;
        for i in touchBar!.itemIdentifiers{
            if(i == .flexibleSpace){
                continue
            }
            count += 1
        }
        if case .began = recognizer.state {
            songArtworkTitleButton?.title =
                recognizer.translation(in: songArtworkTitleButton).x > 0 ?
                    (count < 5) ?
                        song.name: song.name.truncate(at: songTitleMaximumLength) :
                (count<5) ?
                song.artist: song.artist.truncate(at: songTitleMaximumLength)
        }
    }
    
    func prepareSoundSlider() {
        soundSlider?.target          = self
        soundSlider?.slider.minValue = 0.0
        soundSlider?.slider.maxValue = 100.0
        soundSlider?.action          = #selector(soundSliderValueChanged(_:))
        
        soundSlider?.minimumValueAccessory = NSSliderAccessory(image: NSImage.volumeLow!)
        soundSlider?.maximumValueAccessory = NSSliderAccessory(image: NSImage.volumeHigh!)
        soundSlider?.valueAccessoryWidth   = .wide
        
        // Set the player volume on the slider
        soundSlider?.slider.integerValue = helper.volume
    }

    func prepareShuffleRepeatSegmentedView() {
        shuffleRepeatSegmentedView?.target       = self
        shuffleRepeatSegmentedView?.segmentCount = 2
        shuffleRepeatSegmentedView?.segmentStyle = .separated
        shuffleRepeatSegmentedView?.trackingMode = .selectAny
        shuffleRepeatSegmentedView?.action       = #selector(shuffleRepeatSegmentedViewClicked(_:))
        
        // Set image for 'shuffle' button
        shuffleRepeatSegmentedView?.setImage(.shuffling, forSegment: 0)
        
        // Set image for 'repeat' button
        shuffleRepeatSegmentedView?.setImage(.repeating, forSegment: 1)
        
        updateShuffleRepeatSegmentedView()
    }
    
    func prepareLaunchAtLoginButton() {
        launchAtLoginButton?.target       = self
        launchAtLoginButton?.segmentCount = 1
        launchAtLoginButton?.segmentStyle = .separated
        launchAtLoginButton?.trackingMode = .selectAny
        launchAtLoginButton?.action       = #selector(launchAtLoginButtonClicked(_:))
        
        launchAtLoginButton?.setLabel("Launch at Login", forSegment: 0)
        
        updateLaunchAtLoginButton()
    }
    
    func prepareQuitButton() {
        quitButton?.target       = self
        quitButton?.action       = #selector(quitButtonClicked(_:))
    }
    
    // MARK: URL events handling
    
    func initEventManager() {
        NSAppleEventManager.shared().setEventHandler(self,
                                                     andSelector: #selector(handleURLEvent),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }
    
    /**
     Catches URLs with specific prefix (@objc "muse://")
     */
    @objc func handleURLEvent(event: NSAppleEventDescriptor,
                        replyEvent: NSAppleEventDescriptor) {
        if  let urlDescriptor = event.paramDescriptor(forKeyword: keyDirectObject),
            let urlString     = urlDescriptor.stringValue,
            let urlComponents = URLComponents(string: urlString),
            let queryItems    = (urlComponents.queryItems as [NSURLQueryItem]?) {
            
            // Get "code=" parameter from URL
            // https://gist.github.com/gillesdemey/509bb8a1a8c576ea215a
            let code = queryItems.filter({ (item) in item.name == "code" }).first?.value!
            
            // Send code to SpotifyHelper -> Swiftify
            if let helper = helper as? SpotifyHelper, let authorizationCode = code {
                helper.saveToken(from: authorizationCode)
            }
        }
    }
    
    // MARK: Notification handling
    
    func initNotificationWatchers() {
        // Set up player and system wake event watchers
        initPlayerNotificationWatchers()
        initWakeNotificationWatcher()
    }
    
    func initWakeNotificationWatcher() {
        // Attach the NotificationObserver for system wake notification
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                            object: nil,
                                                            queue: nil,
                                                            using: hookWakeNotification)
    }
    
    func hookWakeNotification(notification: Notification) {
        // Reset and reload touchBar when system wakes up
        touchBar                = nil
        didPresentAsSystemModal = false
    }
    
    func initPlayerNotificationWatchers() {
        for (_, notification) in manager.TrackChangedNotifications {
            // Attach the NotificationObserver for Spotify notifications
            DistributedNotificationCenter.default().addObserver(forName: notification,
                                                                object: nil,
                                                                queue: nil,
                                                                using: hookPlayerNotification)
        }
    }
    
    func deinitPlayerNotificationWatchers() {
        for (_, notification) in manager.TrackChangedNotifications {
            // Remove the NotificationObserver
            DistributedNotificationCenter.default().removeObserver(self,
                                                                   name: notification,
                                                                   object: nil)
        }
    }
    
    func isClosing(with notification: Notification) -> Bool {
        guard let userInfo = notification.userInfo else { return false }
        
        // This is only for Spotify and iTunes!
        if notification.name.rawValue == SpotifyHelper.rawTrackChangedNotification {
            // If the notification has only one item
            // that's the PlayerStateStopped -> player is closing
            return userInfo.count < 2
        } else if notification.name.rawValue == iTunesHelper.rawTrackChangedNotification {
            // For iTunes, since it sends a complete notification
            // we must check its content is somehow different from
            // last saved state (the one UI has)
            // TODO: find a way to make it work when closing from playing state
            guard   let name = userInfo[iTunesNotificationTrackName]    as? String,
                    let state = userInfo[iTunesNotificationPlayerState] as? String
            else { return userInfo.count < 2 }
            
            return  name == self.song.name &&
                    (state == iTunesNotificationPlayerStatePlaying) == isUIPlaying
        }
        
        return false
    }
    
    func hookPlayerNotification(notification: Notification) {
        // When Spotify is quitted, it sends an NSNotification
        // with only PlayerStateStopped, that causes it to
        // reopen for being polled by Muse
        // So we detect if the notification is a closing one
        guard !isClosing(with: notification) else {
            handleClosing()
            return
        }
        
        // Switch to a new helper
        // If the notification is sent from another player
        guard notification.name == helper.TrackChangedNotification else {
            setPlayerHelper(to: manager.designatedHelperID)
            return
        }
        
        if shouldLoadSong {
            handleNewSong()
        } else {
            handlePlayPause()
        }
        
        trackSongProgress()
        
        // Reset event sending check
        eventSentFromApp = false
    }
    
    func resetSong() {
        // Set placeholder value
        // TODO: update artwork with some blank
        song = Song()
        
        // This avoids reopening while playing too
        deinitSongTrackingTimer()
        
        // TODO: Disabled because was causing player to reopen
        //       Find a proper way to reset song data and update!
        // updateAfterNotification()
        
        // Reset song progress slider
        updateSongProgressSlider(with: 0)
    }
    
    func handleClosing() {
        resetSong()
    }
    
    func handleNewSong() {
        // New track notification
        willChangeValue(forKey: kSong)
        
        // Retrieve new value
        song = helper.song
        
        didChangeValue(forKey: kSong)
        
        updateSongProgressSlider()
        
        updateAfterNotification()
    }
    
    func handlePlayPause() {
        // Play/pause notification
        updateControlsAfterPlayPause()
        
        // Set play/pause and update elapsed time on the TouchBar
        updatePlaybackState()
        updateNowPlayingInfoElapsedPlaybackTime(with: helper.playbackPosition)
    }
    
    var shouldLoadSong: Bool {
        // A new song should be fully reloaded only
        // if it's an actually different track
        return helper.song.name != song.name
    }
    
    // MARK: Playback progress handling
    
    func trackSongProgress() {
        if songTrackingTimer.isValid { deinitSongTrackingTimer() }
        
        if helper.isPlaying {
            songTrackingTimer = Timer.scheduledTimer(timeInterval: 1,
                                                     target: self,
                                                     selector: #selector(syncSongProgressSlider),
                                                     userInfo: nil,
                                                     repeats: true)
            
            // Set timer tolerance
            // Improves performance by giving the system more headroom
            // for polling frequency. 
            songTrackingTimer.tolerance = 0.1
        } else {
            syncSongProgressSlider()
        }
    }
    
    func deinitSongTrackingTimer() {
        // Invalidates the progress timer
        // e.g. when switching to a different song or on app close
        songTrackingTimer.invalidate()
    }
    
    func updateSongProgressSlider(with position: Double = -1) {
        if !helper.doesSendPlayPauseNotification {
            // If the player does not send a play/pause notification
            // we must manually check if state has changed
            // This means the timer cannot be stopped though...
            // TODO: find a better way to do this
            if isUIPlaying != helper.isPlaying {
                handlePlayPause()
            }
        }
        
        if helper.playbackPosition > song.duration && song.duration == 0 {
            // Hotfix for occasional song loading errors
            // TODO: Check if this is actually working
            song = helper.song
        }
        
        let position = position > -1 ? position : helper.playbackPosition
        
        songProgressSlider?.doubleValue = position / song.duration
        
        if isUIPlaying {
            updateControlStripButton()
        }
        
        // Also update native touchbar scrubber
        updateNowPlayingInfoElapsedPlaybackTime(with: position)
    }
    
    @objc func syncSongProgressSlider() {
        guard helper.playerState != .stopped else {
            // Reset song data if player is stopped
            resetSong()
            return
        }
        // Convenience call for updating the progress slider during playback
        if !isSliding { updateSongProgressSlider() }
    }
    
    func updateControlsAfterPlayPause() {
        isUIPlaying = helper.isPlaying
        
        controlsSegmentedView?.setImage(isUIPlaying ? .pause : .play,
                                        forSegment: 1)
    }
    
    func setShuffleRepeatSegmentedView(shuffleSelected: Bool? = nil, repeatSelected: Bool? = nil) {
        // Select 'shuffle' button
        if let shuffleSelected = shuffleSelected {
            shuffleRepeatSegmentedView?.setSelected(shuffleSelected, forSegment: 0)
        }
        
        // Select 'repeat' button
        if let repeatSelected = repeatSelected {
            shuffleRepeatSegmentedView?.setSelected(repeatSelected, forSegment: 1)
        }
    }
    
    func updateLaunchAtLoginButton() {
        // Update Launch at Login status
        launchAtLoginButton?.setSelected(LoginServiceKit.isExistLoginItems(), forSegment: 0)
    }
    
    func updateShuffleRepeatSegmentedView() {
        // Convenience call for updating the 'repeat' and 'shuffle' buttons
        setShuffleRepeatSegmentedView(shuffleSelected: helper.shuffling,
                                      repeatSelected: helper.repeating)
    }
    
    func updateLikeButton(newValue: Bool? = nil) {
        if let liked = newValue {
            setLikeButton(value: liked)
            return
        }
        
        // Updates like button according to player support and track status
        if let helper = helper as? SpotifyHelper {
            likeButton?.isEnabled = true
            
            // Spotify needs async saved loading from Web API 
            helper.isSaved { saved in
                self.setLikeButton(value: saved)
            }
        } else if let helper = helper as? LikablePlayerHelper {
            likeButton?.isEnabled = true

            setLikeButton(value: helper.liked)
        } else {
            likeButton?.isEnabled = false
            
            setLikeButton(value: true)
        }
    }
    
    func setLikeButton(value: Bool) {
        likeButton?.image = value ? .liked : .like
    }
    
    func updateLikeButtonColdStart() {
        // Fetches the like status after time delay
        DispatchQueue.main.run(after: 200) {
            self.updateLikeButton()
        }
    }
    
    func updateSoundPopoverButton(for volume: Int) {
        // Change the popover icon based on current volume
        if (volume > 70) {
            soundPopoverButton?.collapsedRepresentationImage = .volumeHigh
        } else if (volume > 30) {
            soundPopoverButton?.collapsedRepresentationImage = .volumeMedium
        } else {
            soundPopoverButton?.collapsedRepresentationImage = .volumeLow
        }
    }
    
    // MARK: Deinitialization
    
    func windowWillClose(_ notification: Notification) {
        // Remove the observer when window is closed
        deinitPlayerNotificationWatchers()
        
        // Invalidate progress timer
        deinitSongTrackingTimer()
    }
    
    // MARK: UI refresh
    
    func updateAfterNotification(updateNowPlaying: Bool = true) {
        updateUIAfterNotification()
        
        if updateNowPlaying {
            // Also update TouchBar media controls
            updateNowPlayingInfo()
        }
    }
    
    func updateUIAfterNotification() {
        isUIPlaying = helper.isPlaying
        
        updateTouchBarUI()
    }
    
    var image: NSImage = .defaultBg {
        didSet {
            self.updateArtworkColorAndSize(for: image)
        }
    }
    
    func fetchArtwork() {
        if  let stringURL = helper.artwork() as? String,
            let artworkURL = URL(string: stringURL) {
            NSImage.download(from: artworkURL,
                             fallback: .defaultBg) { self.image = $0 }
        } else if let image = helper.artwork() as? NSImage {
            self.image = image
        } else if   let descriptor = helper.artwork() as? NSAppleEventDescriptor,
            let image = NSImage(data: descriptor.data) {
            // Handles PNG artwork images
            self.image = image
        } else if song.isValid {
            // If we have song info but no cover
            // we try fetching the image from Spotify servers
            // providing title and artist name
            // TODO: more testing!
            SpotifyHelper.shared.fetchTrackInfo(title: self.song.name,
                                                artist: self.song.artist)
            { track in
                guard let album = track.album else { return }
                
                NSImage.download(from: URL(string: album.artUri)!,
                                 fallback: .defaultBg) { self.image = $0 }
            }
        } else {
            self.image = NSImage.defaultBg
        }
    }
    
    func updateTouchBarUI() {
        var count = 0;
        for i in touchBar!.itemIdentifiers {
            if(i == .flexibleSpace){
                continue
            }
            count += 1
        }
        
        if(count < 5){
            if(songProgressSlider?.constraints.count==1){
            songProgressSlider?.addWidthConstraint(size: 210)
            }
            songArtworkTitleButton?.title = song.name
        
            songArtworkTitleButton?.sizeToFit()
        
        }else{
            if(songProgressSlider?.constraints.count==2){
            songProgressSlider?.removeConstraint((songProgressSlider?.constraints[1])!)
                
            }
            songArtworkTitleButton?.title = song.name.truncate(at: songTitleMaximumLength)
            
            songArtworkTitleButton?.sizeToFit()
            
        }
        controlsSegmentedView?.setImage(helper.isPlaying ? .pause : .play,
                                       forSegment: 1)
        
        fetchArtwork()
 
        updateLikeButton()
    }
    
    func updateArtworkColorAndSize(for image: NSImage) {
        // Resize image to fit TouchBar view
        // TODO: Move this elsewhere
        songArtworkTitleButton?.image = image.resized(to: NSMakeSize(30, 30))
        
        if image != .defaultBg {
            controlStripButton?.image = image.resized(to: controlStripButtonSize)
                                             .withAlpha(0.3)
        } else {
            controlStripButton?.image = nil
        }
    }
    
}

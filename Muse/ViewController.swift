//
//  ViewController.swift
//  Muse
//
//  Created by Marco Albera on 21/11/16.
//  Copyright © 2016 Edge Apps. All rights reserved.
//

import Cocoa
import QuartzCore

// MARK: ActionInfo

// Defines a set of infos to inform the VC
// about player events from the outside
enum PlayerAction {
    case play
    case pause
    case previous
    case next
}

// MARK: ViewController

@available(OSX 10.12.2, *)
class ViewController: NSViewController {
    
    // MARK: Properties
    
    // Button images
    var previousImage = NSImage.previous
    var playImage     = NSImage.play
    var pauseImage    = NSImage.pause
    var nextImage     = NSImage.next
    
    // Action view auto close
    let actionViewTimeout: TimeInterval = 0.75 // Timeout in seconds
    var autoCloseTimer:    Timer        = Timer() // The timer
    
    // MARK: Helpers
    
    var helper: PlayerHelper {
        guard let window = self.view.window, let windowController = window.windowController as? WindowController else {
            // Default helper
            return PlayersManager.shared.defaultHelper
        }
        
        // Returns helper from WindowController
        // TODO: Move helper outside WC
        return windowController.helper
    }
    
    // MARK: Outlets

    @IBOutlet weak var fullSongArtworkView: ImageView!
    
    @IBOutlet weak var titleLabelView: NSTextField!
    @IBOutlet weak var albumArtistLabelView: NSTextField!
    
    @IBOutlet weak var previousTrackButton: NSButton!
    @IBOutlet weak var togglePlayPauseButton: NSButton!
    @IBOutlet weak var nextTrackButton: NSButton!
    
    @IBOutlet weak var songProgressSlider: NSSlider!
    
    @IBOutlet weak var actionImageView: NSImageView!
    
    // MARK: Superviews
    
    var titleAlbumArtistSuperview: NSView!
    var controlsSuperview: NSView!
    var actionSuperview: NSView!
    
    // MARK: Actions
    
    @IBAction func previousTrackButtonClicked(_ sender: Any) {
        helper.previousTrack()
    }
    
    @IBAction func togglePlayPauseButtonClicked(_ sender: Any) {
        helper.togglePlayPause()
    }
    
    @IBAction func nextTrackButtonClicked(_ sender: Any) {
        helper.nextTrack()
    }
    
    @IBAction func songProgressSliderValueChanged(_ sender: Any) {
        // Track progress slider changes
        if let slider = sender as? NSSlider {
            guard let currentEvent = NSApplication.shared().currentEvent else { return }
            
            if (currentEvent.type == .leftMouseDown) {
                // Detected mouse down
                helper.scrub(touching: true)
            }
            
            if (currentEvent.type == .leftMouseUp) {
                // Detected mouse up
                helper.scrub(to: slider.doubleValue)
            }
        }
    }
    
    // MARK: UI preparation
    
    override func viewDidLoad() {
        super.viewDidLoad()

        titleAlbumArtistSuperview = titleLabelView.superview
        controlsSuperview         = togglePlayPauseButton.superview
        actionSuperview           = actionImageView.superview
        
        titleAlbumArtistSuperview.wantsLayer = true
        controlsSuperview.wantsLayer         = true
        actionSuperview.wantsLayer           = true
    }
    
    override func viewWillAppear() {
        setBackgroundAndShadow(for: titleAlbumArtistSuperview)
        setBackgroundAndShadow(for: controlsSuperview)
        
        prepareSongProgressSlider()
        prepareFullSongArtworkView()
        prepareLastActionView()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    func setBackgroundAndShadow(for superview: NSView!) {
        guard let layer = superview.layer else { return }
        
        // Set background color
        layer.backgroundColor = NSColor.controlColor.cgColor
        
        // Set the shadow
        superview.shadow = NSShadow()
        setShadow(for: layer)
    }
    
    func setShadow(for layer: CALayer) {
        // Create shadow
        layer.shadowColor = NSColor.controlShadowColor.cgColor
        layer.shadowRadius = 0.5
        layer.shadowOpacity = 1
    }
    
    func prepareSongProgressSlider() {
        guard let cell = self.songProgressSlider.cell as? SliderCell else { return }
        
        // Hide slider thumb
        cell.knobImage = NSImage()
        cell.knobVisible = false
    }
    
    func prepareFullSongArtworkView() {
        // Set image scaling
        fullSongArtworkView.imageScaling = .scaleAxesIndependently
        
        // Add callback to show/hide views when hovering (animating)
        fullSongArtworkView.mouseHandler = {
            (mouseHovering: Bool) -> Void in
            self.titleAlbumArtistSuperview.animator().isHidden = !mouseHovering
            self.controlsSuperview.animator().isHidden = !mouseHovering
        }
    }
    
    func prepareLastActionView() {
        guard let layer = actionSuperview.layer else { return }
        
        // Set radius
        layer.cornerRadius = 7.5
        layer.masksToBounds = true
        
        // Set shadow
        actionSuperview.shadow = NSShadow()
        setShadow(for: layer)
    }
    
    // MARK: UI activation
    
    func showLastActionView(for action: PlayerAction) {
        // Only show action info if mouse is not hovering
        guard controlsSuperview.isHidden else { return }
        
        // Invalidate existing timers
        // This prevents calls from precedent ones
        autoCloseTimer.invalidate()
        
        switch action {
        case .play:
            actionImageView.image = playImage
        case .pause:
            actionImageView.image = pauseImage
        case .previous:
            actionImageView.image = previousImage
        case .next:
            actionImageView.image = nextImage
        }
        
        // Show the view
        actionSuperview.animator().isHidden = false
        
        // Restart the autoclose timer
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: actionViewTimeout,
                                              repeats: false) { timer in
            // Hide the view and invalidate the timer
            self.actionSuperview.animator().isHidden = true
            timer.invalidate()
        }
    }
    
    // MARK: UI refresh
    
    func updateButtons() {
        // Initialize playback control buttons
        previousTrackButton.image = previousImage
        togglePlayPauseButton.image = helper.isPlaying ? pauseImage : playImage
        nextTrackButton.image = nextImage
    }
    
    func updateFullSongArtworkView(with object: Any?) {
        // Update the artwork view with an image URL
        if let url = object as? URL {
            fullSongArtworkView.loadImage(from: url, callback: { _ in })
        // Or an NSImage
        } else if let image = object as? NSImage {
            fullSongArtworkView.image = image
        }
        
        // Update the colors with a completion handler
        // This avoids blocking the main UI thread
        fullSongArtworkView.image?.getColors(scaleDownSize: NSMakeSize(25, 25)) { colors in
            // We also set an aggressive scaling size
            // to optimize performace and memory usage
            self.colorViews(with: colors)
        }
    }
    
    func colorButtonImages(with color: NSColor) {
        // Update button images with new color
        previousImage = NSImage.previous?.tint(with: color)
        playImage     = NSImage.play?.tint(with: color)
        pauseImage    = NSImage.pause?.tint(with: color)
        nextImage     = NSImage.next?.tint(with: color)
        
        // Color action image too
        actionImageView.image = actionImageView.image?.tint(with: color)
    }
    
    func colorViews(with colors: ImageColors) {
        // Blend the background color with 'lightGray'
        // This prevents view from getting too dark
        let backgroundColor = colors.background.blended(withFraction: 0.5, of: .lightGray)?.cgColor
        let primaryColor = colors.primary.blended(withFraction: 0.5, of: .lightGray)
        let secondaryColor = colors.secondary.blended(withFraction: 0.5, of: .lightGray)
        
        let buttonColor = colors.primary.blended(withFraction: 0.5, of: .lightGray)
        
        // Set the superview background color and animate it
        titleAlbumArtistSuperview.layer?.animateChange(to: backgroundColor!,
                                                       for: CALayer.kBackgroundColorPath)
        controlsSuperview.layer?.animateChange(to: backgroundColor!,
                                               for: CALayer.kBackgroundColorPath)
        actionSuperview.layer?.animateChange(to: backgroundColor!,
                                                 for: CALayer.kBackgroundColorPath)
        
        // Set the text colors
        titleLabelView.textColor = primaryColor
        albumArtistLabelView.textColor = secondaryColor
        
        // Set color on the slider too
        if let cell = songProgressSlider.cell as? SliderCell {
            cell.backgroundColor = primaryColor!
            cell.highlightColor = secondaryColor!
        }
        
        // Set the color on the playback buttons
        colorButtonImages(with: buttonColor!)
        updateButtons()
    }
    
    func updateTitleAlbumArtistView(for song: Song) {
        titleLabelView.stringValue = song.name
        
        albumArtistLabelView.stringValue = "\(song.artist) - \(song.album)"
    }
    
    func updateSongProgressSlider(with position: Double) {
        songProgressSlider.doubleValue = position
    }
    
}


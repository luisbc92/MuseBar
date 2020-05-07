## <img src=Muse/Resources/Assets.xcassets/AppIcon.appiconset/icon-512@2x.png width="32"> Muse Bar

An open-source Spotify, Apple Music and Vox Touch Bar controller, system-wide TouchBar controls and Spotify account integration.

[Download](https://github.com/planecore/MuseBar/raw/master/Muse%20Bar.zip)

<img src=Screenshots/Now%20Playing.png>

<img src=Screenshots/Muse%20Bar%20Main.png>

<img src=Screenshots/Muse%20Bar%20Secondary.png>

### Control strip integration
Muse appends a permanent button to the control strip (right tray bar) of the TouchBar, displaying album art and playback time. You can tap it to reveal the full control bar, long press it to toggle play/pause and swipe on it to jump to next or previous track.

### Installation
At first start you'll be prompted to log into your Spotify account. It's not strictly necessary but it allows adding/removing favourites to your library.

### Usage
When you open Muse Bar you'll see a new button as the leftmost part of of the control strip on your TouchBar.
Tap it to play/pause.
Flick left/right to go to the previous/next song.
Long tap to show Muse Bar controls.

To quit Muse Bar, long tap the Muse Bar button on the control strip, then tap on the volume icon and tap Quit.

Spotify, Apple Music and Vox are currently supported. The app automatically guesses the right player to control basing on availability and playback notifications.

### Build
Just clone the repository, install the pods and open the workspace file.
```
git clone https://github.com/planecore/MuseBar && cd MuseBar/ && pod install && open Muse.xcworkspace
```

### Libraries
- [SpotifyKit](https://github.com/xzzz9097/SpotifyKit) by @xzzz9097
- [NSImageColors](https://github.com/xzzz9097/NSImageColors) by @jathu

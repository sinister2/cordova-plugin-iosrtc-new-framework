import Foundation
import AVFoundation
import WebRTC

// NOTE: RTCEAGLVideoView/RTCEAGLVideoViewDelegate were removed.
// Use RTCMTLVideoView and RTCVideoViewDelegate instead.
class PluginMediaStreamRenderer: NSObject, RTCVideoViewDelegate {

    var id: String
    var eventListener: (_ data: NSDictionary) -> Void
    var closed: Bool

    var webView: UIView
    var elementView: UIView
    var pluginMediaStream: PluginMediaStream?

    var videoView: RTCMTLVideoView
    var rtcAudioTrack: RTCAudioTrack?
    var rtcVideoTrack: RTCVideoTrack?
    var pluginVideoTrack: PluginMediaStreamTrack?

    init(
        webView: UIView,
        eventListener: @escaping (_ data: NSDictionary) -> Void
    ) {
        NSLog("PluginMediaStreamRenderer#init()")

        // Open Renderer
        self.id = UUID().uuidString
        self.closed = false

        // The browser HTML view.
        self.webView = webView
        self.eventListener = eventListener

        let useManualLayoutRenderer = Bundle.main.object(forInfoDictionaryKey: "UseManualLayoutRenderer") as? Bool ?? false

        // The video element view.
        let guide = webView.safeAreaLayoutGuide
        self.elementView = useManualLayoutRenderer
            ? UIView(frame: CGRect(x: 0.0, y: guide.layoutFrame.minY, width: guide.layoutFrame.width, height: guide.layoutFrame.height))
            : UIView()

        // Effective video view (Metal).
        self.videoView = RTCMTLVideoView()
        self.videoView.isUserInteractionEnabled = false

        self.elementView.isUserInteractionEnabled = false
        self.elementView.isHidden = true
        self.elementView.backgroundColor = UIColor.black
        self.elementView.addSubview(self.videoView)
        self.elementView.layer.masksToBounds = true
        self.elementView.translatesAutoresizingMaskIntoConstraints = false

        // Place the video element view inside the WebView's superview
        self.webView.addSubview(self.elementView)
        self.webView.isOpaque = false
        self.webView.backgroundColor = UIColor.clear

        // Layout to safe area
        let view = self.elementView
        if !useManualLayoutRenderer {
            if #available(iOS 11.0, *) {
                view.topAnchor.constraint(equalTo: guide.topAnchor).isActive = true
                view.bottomAnchor.constraint(equalTo: guide.bottomAnchor).isActive = true
                view.leftAnchor.constraint(equalTo: guide.leftAnchor).isActive = true
                view.rightAnchor.constraint(equalTo: guide.rightAnchor).isActive = true
            } else {
                NSLayoutConstraint(item: view, attribute: .top, relatedBy: .equal, toItem: webView, attribute: .top, multiplier: 1.0, constant: 0).isActive = true
                NSLayoutConstraint(item: view, attribute: .bottom, relatedBy: .equal, toItem: webView, attribute: .bottom, multiplier: 1.0, constant: 0).isActive = true
                NSLayoutConstraint(item: view, attribute: .leading, relatedBy: .equal, toItem: webView, attribute: .leading, multiplier: 1.0, constant: 0).isActive = true
                NSLayoutConstraint(item: view, attribute: .trailing, relatedBy: .equal, toItem: webView, attribute: .trailing, multiplier: 1.0, constant: 0).isActive = true
            }
        }
    }

    deinit {
        NSLog("PluginMediaStreamRenderer#deinit()")
    }

    func run() {
        NSLog("PluginMediaStreamRenderer#run()")
        self.videoView.delegate = self
    }

    func render(_ pluginMediaStream: PluginMediaStream) {
        NSLog("PluginMediaStreamRenderer#render()")

        if self.pluginMediaStream != nil {
            self.reset()
        }

        self.pluginMediaStream = pluginMediaStream

        // Take the first audio track.
        for (_, track) in pluginMediaStream.audioTracks {
            self.rtcAudioTrack = track.rtcMediaStreamTrack as? RTCAudioTrack
            break
        }

        // Take the first video track.
        for (_, track) in pluginMediaStream.videoTracks {
            self.pluginVideoTrack = track
            self.rtcVideoTrack = track.rtcMediaStreamTrack as? RTCVideoTrack
            break
        }

        if let rtcVideoTrack = self.rtcVideoTrack {
            rtcVideoTrack.add(self.videoView)
            self.pluginVideoTrack?.registerRender(render: self)
        }
    }

    func mediaStreamChanged() {
        NSLog("PluginMediaStreamRenderer#mediaStreamChanged()")

        guard self.pluginMediaStream != nil else { return }

        let oldPluginVideoTrack: PluginMediaStreamTrack? = self.pluginVideoTrack
        let oldRtcVideoTrack: RTCVideoTrack? = self.rtcVideoTrack

        self.rtcAudioTrack = nil
        self.rtcVideoTrack = nil
        self.pluginVideoTrack = nil

        // Take the first audio track.
        for (_, track) in self.pluginMediaStream!.audioTracks {
            self.rtcAudioTrack = track.rtcMediaStreamTrack as? RTCAudioTrack
            break
        }

        // Take the first video track.
        for (_, track) in pluginMediaStream!.videoTracks {
            self.pluginVideoTrack = track
            self.rtcVideoTrack = track.rtcMediaStreamTrack as? RTCVideoTrack
            break
        }

        // If same video track as before do nothing.
        if let old = oldRtcVideoTrack, let current = self.rtcVideoTrack, old.trackId == current.trackId {
            NSLog("PluginMediaStreamRenderer#mediaStreamChanged() | same video track as before")
        }
        // Different video track.
        else if let old = oldRtcVideoTrack, let current = self.rtcVideoTrack, old.trackId != current.trackId {
            NSLog("PluginMediaStreamRenderer#mediaStreamChanged() | has a new video track")
            oldPluginVideoTrack?.unregisterRender(render: self)
            old.remove(self.videoView)
            self.pluginVideoTrack?.registerRender(render: self)
            current.add(self.videoView)
        }
        // Did not have video but now it has.
        else if oldRtcVideoTrack == nil, let current = self.rtcVideoTrack {
            NSLog("PluginMediaStreamRenderer#mediaStreamChanged() | video track added")
            oldPluginVideoTrack?.unregisterRender(render: self)
            self.pluginVideoTrack?.registerRender(render: self)
            current.add(self.videoView)
        }
        // Had video but now it has not.
        else if let old = oldRtcVideoTrack, self.rtcVideoTrack == nil {
            NSLog("PluginMediaStreamRenderer#mediaStreamChanged() | video track removed")
            oldPluginVideoTrack?.unregisterRender(render: self)
            old.remove(self.videoView)
        }
    }

    func refresh(_ data: NSDictionary) {

        let elementLeft = data.object(forKey: "elementLeft") as? Double ?? 0
        let elementTop = data.object(forKey: "elementTop") as? Double ?? 0
        let elementWidth = data.object(forKey: "elementWidth") as? Double ?? 0
        let elementHeight = data.object(forKey: "elementHeight") as? Double ?? 0
        var videoViewWidth = data.object(forKey: "videoViewWidth") as? Double ?? 0
        var videoViewHeight = data.object(forKey: "videoViewHeight") as? Double ?? 0
        let visible = data.object(forKey: "visible") as? Bool ?? true
        let opacity = data.object(forKey: "opacity") as? Double ?? 1
        let zIndex = data.object(forKey: "zIndex") as? Double ?? 0
        let mirrored = data.object(forKey: "mirrored") as? Bool ?? false
        let clip = data.object(forKey: "clip") as? Bool ?? true
        let borderRadius = data.object(forKey: "borderRadius") as? Double ?? 0
        let backgroundColor = data.object(forKey: "backgroundColor") as? String ?? "0,0,0"

        NSLog("PluginMediaStreamRenderer#refresh() [elementLeft:%@, elementTop:%@, elementWidth:%@, elementHeight:%@, videoViewWidth:%@, videoViewHeight:%@, visible:%@, opacity:%@, zIndex:%@, mirrored:%@, clip:%@, borderRadius:%@]",
              String(elementLeft), String(elementTop), String(elementWidth), String(elementHeight),
              String(videoViewWidth), String(videoViewHeight), String(visible), String(opacity), String(zIndex),
              String(mirrored), String(clip), String(borderRadius))

        let videoViewLeft: Double = (elementWidth - videoViewWidth) / 2
        let videoViewTop: Double = (elementHeight - videoViewHeight) / 2

        self.elementView.frame = CGRect(
            x: CGFloat(elementLeft + self.webView.safeAreaInsets.left),
            y: CGFloat(elementTop + self.webView.safeAreaInsets.top),
            width: CGFloat(elementWidth),
            height: CGFloat(elementHeight)
        )

        // Avoid zero-size view.
        if videoViewWidth == 0 || videoViewHeight == 0 {
            videoViewWidth = 1
            videoViewHeight = 1
            self.videoView.isHidden = true
        } else {
            self.videoView.isHidden = false
        }

        self.videoView.frame = CGRect(
            x: CGFloat(videoViewLeft),
            y: CGFloat(videoViewTop),
            width: CGFloat(videoViewWidth),
            height: CGFloat(videoViewHeight)
        )

        self.elementView.isHidden = !visible
        self.elementView.alpha = CGFloat(opacity)
        self.elementView.layer.zPosition = CGFloat(zIndex)

        if zIndex == 0 {
            self.webView.bringSubviewToFront(self.elementView)
        }

        if !mirrored {
            self.elementView.transform = CGAffineTransform.identity
        } else {
            self.elementView.transform = CGAffineTransform(scaleX: -1.0, y: 1.0)
        }

        self.elementView.clipsToBounds = clip
        self.elementView.layer.cornerRadius = CGFloat(borderRadius)
        let rgb = backgroundColor.components(separatedBy: ",").map { CGFloat(($0 as NSString).floatValue) / 256.0 }
        let color = UIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        self.elementView.backgroundColor = color
    }

    func save(callback: (_ data: String) -> Void,
              errback: (_ error: String) -> Void) {
        UIGraphicsBeginImageContextWithOptions(videoView.bounds.size, videoView.isOpaque, 0.0)
        videoView.drawHierarchy(in: videoView.bounds, afterScreenUpdates: false)
        let snapshotImageFromMyView = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        let imageData = snapshotImageFromMyView?.jpegData(compressionQuality: 1.0)
        let strBase64 = imageData?.base64EncodedString(options: .lineLength64Characters)
        callback(strBase64 ?? "")
    }

    func stop() {
        NSLog("PluginMediaStreamRenderer | video stop")
        self.eventListener([
            "type": "videostop"
        ])
    }

    func close() {
        NSLog("PluginMediaStreamRenderer#close()")
        self.closed = true
        self.reset()
        self.elementView.removeFromSuperview()
    }

    // MARK: - Private

    fileprivate func reset() {
        NSLog("PluginMediaStreamRenderer#reset()")
        if let track = self.rtcVideoTrack {
            track.remove(self.videoView)
        }
        self.pluginVideoTrack?.unregisterRender(render: self)
        self.pluginVideoTrack = nil
        self.pluginMediaStream = nil
        self.rtcAudioTrack = nil
        self.rtcVideoTrack = nil
    }

    // MARK: - RTCVideoViewDelegate

    // Note: delegate is Obj-C → method must be @objc and the class must inherit from NSObject.
    @objc func videoView(_ videoView: (any RTCVideoRenderer)?,
                         didChangeVideoSize size: CGSize) {
        NSLog("PluginMediaStreamRenderer | video size changed [width:%@, height:%@]",
              String(describing: size.width), String(describing: size.height))

        self.eventListener([
            "type": "videoresize",
            "size": [
                "width": Int(size.width),
                "height": Int(size.height)
            ]
        ])
    }

    // (Optional) kept for your internal use; not part of RTCVideoViewDelegate.
    @objc func videoView(_ videoView: (any RTCVideoRenderer)?,
                         didChange frame: RTCVideoFrame?) {
        // no-op
    }
}

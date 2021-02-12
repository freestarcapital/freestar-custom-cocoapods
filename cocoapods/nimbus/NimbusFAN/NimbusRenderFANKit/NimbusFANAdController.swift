//
//  NimbusFANAdController.swift
//  NimbusRenderKit
//
//  Created by Inder Dhir on 1/30/20.
//  Copyright © 2020 Timehop. All rights reserved.
//

import NimbusRenderKit
import FBAudienceNetwork

final class NimbusFANAdController: NSObject {

    /// Visibility /exposure manager for the video ad. Used to manage starting / stopping automatically
    /// This also manages resuming the ad when user foregrounds the app and the ad is visible (the IMA SDK does not auto resume at the moment)
    let visibilityManager: VisibilityManager

    private let ad: NimbusAd
    private let logger: Logger

    var volume = 0
    weak var adRendererDelegate: NimbusFANAdRendererDelegate?
    var fbAdView: FBAdView?
    var fbInterstitialAd: FBInterstitialAd?
    var fbNativeAd: FBNativeAd?

    /// Determines whether ad has registered an impression
    private var hasRegisteredAdImpression = false {
        didSet { triggerImpressionDelegateIfNecessary() }
    }

    private var isAdVisible = false {
        didSet { triggerImpressionDelegateIfNecessary() }
    }
    
    private var is320by50Banner = false
    private var fbAdSize: FBAdSize?

    /// Containing view for the Nimbus static ad controller (webview)
    private weak var container: NimbusAdView?
    public weak var delegate: AdControllerDelegate?
    private weak var adPresentingViewController: UIViewController?

    init(
        ad: NimbusAd,
        container: UIView & VisibilityTrackable,
        visibilityManager: VisibilityManager? = nil,
        logger: Logger,
        delegate: AdControllerDelegate,
        adRendererDelegate: NimbusFANAdRendererDelegate?,
        adPresentingViewController: UIViewController?
    ) {
        self.ad = ad
        self.container = container as? NimbusAdView
        self.visibilityManager = NimbusVisibilityManager(for: container)
        self.logger = logger
        self.delegate = delegate
        self.adRendererDelegate = adRendererDelegate
        self.adPresentingViewController = adPresentingViewController

        super.init()

        self.visibilityManager.delegate = self
        
        guard let placementId = ad.placementId else {
            self.delegate?.didReceiveNimbusError(
                controller: self,
                error: NimbusRenderError.adRenderingFailed(message: "Placement id not valid for FB ad")
            )
            return
        }

        switch (ad.auctionType, ad.isInterstitial) {
        case (.native, _):
            fbNativeAd = FBNativeAd(placementID: placementId)
            fbNativeAd?.delegate = self

            if ad.markup.isEmpty {
                if Nimbus.shared.testMode {
                    // Testing Facebook native ad rendering on the client
                    fbNativeAd?.loadAd()
                } else {
                    delegate.didReceiveNimbusError(
                        controller: self,
                        error: NimbusRenderError.adRenderingFailed(message: "No markup present to render Facebook native ad")
                    )
                }
            } else {
                fbNativeAd?.loadAd(withBidPayload: ad.markup)
            }

        case (.video, _), (.static, true):
            fbInterstitialAd = FBInterstitialAd(placementID: placementId)
            fbInterstitialAd?.delegate = self

            if ad.markup.isEmpty {
                if Nimbus.shared.testMode {
                    // Testing Facebook interstitial ad rendering on the client
                    fbInterstitialAd?.load()
                } else {
                    delegate.didReceiveNimbusError(
                        controller: self,
                        error: NimbusRenderError.adRenderingFailed(message: "No markup present to render Facebook interstitial ad")
                    )
                }
            } else {
                fbInterstitialAd?.load(withBidPayload: ad.markup)
            }

        case (.static, false):
            switch ad.adDimensions?.height {
            case 90: fbAdSize = kFBAdSizeHeight90Banner
            case 250: fbAdSize = kFBAdSizeHeight250Rectangle
            default:
                // Old integration also used to default to 320x50
                fbAdSize = kFBAdSizeHeight50Banner
                is320by50Banner = ad.adDimensions?.width == 320 && ad.adDimensions?.height == 50
            }
            
            loadBannerAd()
        }

        self.visibilityManager.startListeningForVisibilityChanges()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    private func triggerImpressionDelegateIfNecessary() {
        guard let container = container else { return }
        container.visibilityDelegate?.didChangeVisibility(
            controller: container,
            isVisible: isAdVisible,
            hasTriggeredImpression: hasRegisteredAdImpression
        )
    }
    
    private func loadBannerAd() {
        // This is caught at init before this function ever gets called
        guard let placementId = ad.placementId, let fbAdSize = fbAdSize else { return }
        
        fbAdView = FBAdView(
            placementID: placementId,
            adSize: fbAdSize,
            rootViewController: adPresentingViewController
        )
        fbAdView?.delegate = self

        if ad.markup.isEmpty {
            if Nimbus.shared.testMode {
                // Testing Facebook banner ad rendering on the client
                fbAdView?.loadAd()
            } else {
                delegate?.didReceiveNimbusError(
                    controller: self,
                    error: NimbusRenderError.adRenderingFailed(message: "No markup present to render Facebook banner ad")
                )
            }
        } else {
            fbAdView?.loadAd(withBidPayload: ad.markup)
        }
    }
}

// MARK: AdController

extension NimbusFANAdController: AdController {

    var adView: UIView? { return nil }

    var adDuration: CGFloat { return 0 }

    func start() {}

    func stop() {}

    func destroy() {
        fbNativeAd?.unregisterView()
        fbNativeAd = nil
        visibilityManager.destroy()
    }
}

// MARK: Notifications

extension NimbusFANAdController {

    /// Ad is in foreground
    @objc private func appDidBecomeActive() {
        visibilityManager.appDidBecomeActive()
    }

    /// Ad is in background
    @objc private func appWillResignActive() {
        visibilityManager.appWillResignActive()
    }
}

// MARK: VisibilityManagerDelegate

extension NimbusFANAdController: VisibilityManagerDelegate {

    func didRegisterImpressionForView() {}

    func didChangeVisibility(visible: Bool) { isAdVisible = visible }

    func didChangeExposure(exposure: NimbusViewExposure) {}
}

// MARK: FBNativeAdDelegate

extension NimbusFANAdController: FBNativeAdDelegate {

    /// :nodoc:
    func nativeAdDidLoad(_ nativeAd: FBNativeAd) {
        logger.log("FBNativeAd loaded", level: .debug)

        guard nativeAd.isAdValid else {
            delegate?.didReceiveNimbusError(
                controller: self,
                error: NimbusRenderError.adRenderingFailed(message: "FB native ad is invalid")
            )
            return
        }

        guard let container = container else {
            delegate?.didReceiveNimbusError(
                controller: self,
                error: NimbusRenderError.adRenderingFailed(message: "Container view not found for FBNativeAd")
            )
            return
        }

        let fbNativeAdView: UIView
        if let customView = adRendererDelegate?.customViewForRendering(container: container, nativeAd: nativeAd) {
            fbNativeAdView = customView
        } else {
            fbNativeAdView = FBNativeAdView(nativeAd: nativeAd, with: .dynamic)
        }

        fbNativeAdView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(fbNativeAdView)
        if #available(iOS 11.0, *) {
            NSLayoutConstraint.activate([
                fbNativeAdView.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor),
                fbNativeAdView.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor),
                fbNativeAdView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
                fbNativeAdView.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                fbNativeAdView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                fbNativeAdView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                fbNativeAdView.topAnchor.constraint(equalTo: container.topAnchor),
                fbNativeAdView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        delegate?.didReceiveNimbusEvent(controller: self, event: .loaded)

        fbNativeAd = nil
    }

    /// :nodoc:
    func nativeAdWillLogImpression(_ nativeAd: FBNativeAd) {
        logger.log("FBNativeAd will log impression", level: .debug)

        hasRegisteredAdImpression = true

        delegate?.didReceiveNimbusEvent(controller: self, event: .impression)
    }

    /// :nodoc:
    func nativeAd(_ nativeAd: FBNativeAd, didFailWithError error: Error) {
        logger.log("FBNativeAd failed with error: \(error.localizedDescription)", level: .error)

        delegate?.didReceiveNimbusError(
            controller: self,
            error: NimbusRenderError.adRenderingFailed(message: error.localizedDescription)
        )
    }

    /// :nodoc:
    func nativeAdDidClick(_ nativeAd: FBNativeAd) {
        logger.log("FBNativeAd clicked", level: .debug)

        delegate?.didReceiveNimbusEvent(controller: self, event: .clicked)
    }
}

// MARK: FBInterstitialAdDelegate

extension NimbusFANAdController: FBInterstitialAdDelegate {

    /// :nodoc:
    func interstitialAdDidLoad(_ interstitialAd: FBInterstitialAd) {
        logger.log("FBInterstitialAd loaded", level: .debug)

        guard interstitialAd.isAdValid else {
            delegate?.didReceiveNimbusError(
                controller: self,
                error: NimbusRenderError.adRenderingFailed(message: "FB interstitial ad is invalid")
            )
            return
        }

        delegate?.didReceiveNimbusEvent(controller: self, event: .loaded)

        interstitialAd.show(fromRootViewController: adPresentingViewController)

        fbInterstitialAd = nil
    }

    /// :nodoc:
    func interstitialAd(_ interstitialAd: FBInterstitialAd, didFailWithError error: Error) {
        logger.log("FBInterstitialAd failed with error: \(error.localizedDescription)", level: .error)

        delegate?.didReceiveNimbusError(
            controller: self,
            error: NimbusRenderError.adRenderingFailed(message: error.localizedDescription)
        )
    }

    /// :nodoc:
    func interstitialAdWillLogImpression(_ interstitialAd: FBInterstitialAd) {
        logger.log("FBInterstitialAd will log impression", level: .debug)

        delegate?.didReceiveNimbusEvent(controller: self, event: .impression)
    }

    /// :nodoc:
    func interstitialAdDidClick(_ interstitialAd: FBInterstitialAd) {
        logger.log("FBInterstitialAd clicked", level: .debug)

        delegate?.didReceiveNimbusEvent(controller: self, event: .clicked)
    }
}

// MARK: FBAdViewDelegate

extension NimbusFANAdController: FBAdViewDelegate {

    /// :nodoc:
    func adViewDidLoad(_ adView: FBAdView) {
        logger.log("FBAdView loaded", level: .debug)

        guard adView.isAdValid else {
            delegate?.didReceiveNimbusError(
                controller: self,
                error: NimbusRenderError.adRenderingFailed(message: "FB banner ad is invalid")
            )
            return
        }

        guard let container = container else {
            delegate?.didReceiveNimbusError(
                controller: self,
                error: NimbusRenderError.adRenderingFailed(message: "Container view not found for FBAdView")
            )
            return
        }

        adView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(adView)
        if #available(iOS 11.0, *) {
            NSLayoutConstraint.activate([
                adView.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor),
                adView.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor),
                adView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
                adView.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                adView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                adView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                adView.topAnchor.constraint(equalTo: container.topAnchor),
                adView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        delegate?.didReceiveNimbusEvent(controller: self, event: .loaded)
    }

    /// :nodoc:
    func adView(_ adView: FBAdView, didFailWithError error: Error) {
        logger.log("FBAdView failed with error: \(error.localizedDescription)", level: .error)
        
        if is320by50Banner {
            // Retry with the old banner size
            is320by50Banner = false
            fbAdSize = kFBAdSize320x50
            loadBannerAd()
        } else {
            delegate?.didReceiveNimbusError(
                controller: self,
                error: NimbusRenderError.adRenderingFailed(message: error.localizedDescription)
            )
        }
    }

    /// :nodoc:
    func adViewWillLogImpression(_ adView: FBAdView) {
        logger.log("FBAdView will log impression", level: .debug)

        delegate?.didReceiveNimbusEvent(controller: self, event: .impression)
    }

    /// :nodoc:
    func adViewDidClick(_ adView: FBAdView) {
        logger.log("FBAdView clicked", level: .debug)

        delegate?.didReceiveNimbusEvent(controller: self, event: .clicked)
    }
}

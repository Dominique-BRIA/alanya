#import "PontWebrtc.h"
#import <flutter_webrtc/AudioManager.h>
#import <flutter_webrtc/FlutterWebRTCPlugin.h>

@implementation RenduAudioAlanya {
  void (^_bloc)(AVAudioPCMBuffer *tampon);
}

- (instancetype)initAvecBloc:(void (^)(AVAudioPCMBuffer *tampon))bloc {
  self = [super init];
  if (self) {
    _bloc = [bloc copy];
  }
  return self;
}

- (void)renderPCMBuffer:(AVAudioPCMBuffer *)pcmBuffer {
  if (pcmBuffer != nil && _bloc != nil) {
    _bloc(pcmBuffer);
  }
}

@end

@implementation PontWebrtc

static RTCVideoTrack *pisteAffichee = nil;

+ (void)brancherMicro:(RenduAudioAlanya *)rendu {
  [[AudioManager sharedInstance] addLocalAudioRenderer:rendu];
}

+ (void)debrancherMicro:(RenduAudioAlanya *)rendu {
  [[AudioManager sharedInstance] removeLocalAudioRenderer:rendu];
}

+ (void)brancherReception:(RenduAudioAlanya *)rendu {
  [[[AudioManager sharedInstance] renderPreProcessingAdapter] addAudioRenderer:rendu];
}

+ (void)debrancherReception:(RenduAudioAlanya *)rendu {
  [[[AudioManager sharedInstance] renderPreProcessingAdapter] removeAudioRenderer:rendu];
}

+ (BOOL)attacherVideoDistante:(id<RTCVideoRenderer>)vue {
  FlutterWebRTCPlugin *module = [FlutterWebRTCPlugin sharedSingleton];
  if (module == nil) return NO;
  for (RTCPeerConnection *pc in module.peerConnections.allValues) {
    for (RTCRtpReceiver *recepteur in pc.receivers) {
      RTCMediaStreamTrack *piste = recepteur.track;
      if ([piste isKindOfClass:[RTCVideoTrack class]] && piste.readyState == RTCMediaStreamTrackStateLive &&
          piste.isEnabled) {
        RTCVideoTrack *video = (RTCVideoTrack *)piste;
        if (pisteAffichee != nil && pisteAffichee != video) {
          [pisteAffichee removeRenderer:vue];
        }
        [video addRenderer:vue];
        pisteAffichee = video;
        return YES;
      }
    }
  }
  return NO;
}

+ (void)detacherVideo:(id<RTCVideoRenderer>)vue {
  if (pisteAffichee != nil) {
    [pisteAffichee removeRenderer:vue];
    pisteAffichee = nil;
  }
}

+ (void)autoriserCameraMultitache {
  if (@available(iOS 16.0, *)) {
    FlutterWebRTCPlugin *module = [FlutterWebRTCPlugin sharedSingleton];
    AVCaptureSession *session = module.videoCapturer.captureSession;
    if (session != nil && session.isMultitaskingCameraAccessSupported) {
      session.multitaskingCameraAccessEnabled = YES;
    }
  }
}

@end

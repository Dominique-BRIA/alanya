#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

NS_ASSUME_NONNULL_BEGIN

/// Reçoit l'audio d'un appel WebRTC (micro ou correspondant) et le passe à un
/// bloc Swift (`EnregistreurAppel.swift`). Le module WebRTC appelle
/// `renderPCMBuffer:` (voir `AudioProcessingAdapter.m`).
@interface RenduAudioAlanya : NSObject <RTCAudioRenderer>

- (instancetype)initAvecBloc:(void (^)(AVAudioPCMBuffer *tampon))bloc;

@end

/// LE PONT VERS LE MODULE WEBRTC (flutter_webrtc), en Objective-C pour
/// appeler ses méthodes sous leur nom exact.
@interface PontWebrtc : NSObject

/// La voix de l'agent : le micro, après traitement.
+ (void)brancherMicro:(RenduAudioAlanya *)rendu;
+ (void)debrancherMicro:(RenduAudioAlanya *)rendu;

/// La voix du correspondant : l'audio reçu, avant la sortie.
+ (void)brancherReception:(RenduAudioAlanya *)rendu;
+ (void)debrancherReception:(RenduAudioAlanya *)rendu;

/// Affiche la vidéo du correspondant (la première piste vidéo reçue encore
/// vivante) dans `vue`. Rend NO s'il n'y en a pas.
+ (BOOL)attacherVideoDistante:(id<RTCVideoRenderer>)vue;
+ (void)detacherVideo:(id<RTCVideoRenderer>)vue;

/// La caméra continue de filmer quand l'application passe dans la fenêtre
/// flottante (iOS 16 et plus, appareils qui le permettent).
+ (void)autoriserCameraMultitache;

@end

NS_ASSUME_NONNULL_END

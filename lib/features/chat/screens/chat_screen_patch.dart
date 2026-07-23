// PATCH pour chat_screen.dart — remplacer UNIQUEMENT le bloc isAudio dans _bubble()
//
// AVANT :
//   : isAudio
//       ? AudioBubble(
//           url: _mediaUrl(m.media.first),
//           duration: m.media.first.durationMs,
//           onTap: () => InlineAudioPlayer.toggle(...),
//           timestamp: _time(m.createdAt),
//           statusWidget: mine ? _statusTicks(m.status, mine ? Colors.white70 : Colors.black45) : null,
//           isMe: mine,
//         )
//
// APRÈS :
//   : isAudio
//       ? AudioBubble(
//           url: _mediaUrl(m.media.first),
//           duration: m.media.first.durationMs,
//           onTap: () => InlineAudioPlayer.toggle(
//             _mediaUrl(m.media.first),
//             totalDuration: m.media.first.durationMs != null
//                 ? Duration(milliseconds: m.media.first.durationMs!)
//                 : null,
//           ),
//           timestamp: _time(m.createdAt),
//           statusWidget: mine ? _statusTicks(m.status, mine ? Colors.white70 : Colors.black45) : null,
//           isMe: mine,
//         )
//
// NOTE: AudioBubble n'a PLUS de paramètres isPlaying/progress.
// Il écoute InlineAudioPlayer.state directement via ValueListenableBuilder.

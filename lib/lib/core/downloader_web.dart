// ignore: deprecated_member_use
import 'dart:html' as html;

Future<void> downloadUrl(String url, String filename) async {
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..target = "_blank"
    ..style.display = "none";
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}

Future<String?> downloadOnly(String url, String filename) async {
  await downloadUrl(url, filename);
  return null;
}

Future<void> openLocalFile(String path) async {}

Future<String?> getCachedFile(String filename) async => null;

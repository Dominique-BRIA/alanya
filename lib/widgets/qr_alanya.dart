import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// UN QR CODE ALANYA : le code, avec le logo Alanya Work au centre.
///
/// Partagé par le QR permanent du profil et par l'invitation à usage unique,
/// pour que les deux se ressemblent et se lisent pareillement.
///
/// Deux choix qui conditionnent la lecture :
///
///  · 🔴 NIVEAU DE CORRECTION H (30 %). Le logo MASQUE des modules du code ;
///    c'est la redondance du niveau H qui permet au lecteur de les
///    reconstituer. Au niveau par défaut (L, 7 %), le même logo rend le code
///    illisible.
///
///  · ⚠️ LE LOGO EST POSÉ SUR UNE PASTILLE BLANCHE, par-dessus le QR, et non
///    par l'option `embeddedImage` de qr_flutter. Celle-ci dessine l'image
///    PAR-DESSUS les modules sans les effacer : le fond transparent de
///    `logo.png` laisserait voir les carrés noirs au travers du W. La
///    pastille couvre environ 22 % de la largeur, soit 5 % de la surface —
///    bien en deçà de ce que le niveau H sait reconstituer.
///
/// ⚠️ FOND BLANC DANS TOUS LES THÈMES : un QR code sur fond sombre ne se lit
/// pas avec tous les lecteurs.
class QrAlanya extends StatelessWidget {
  final String data;
  final double size;

  const QrAlanya({super.key, required this.data, this.size = 220});

  @override
  Widget build(BuildContext context) {
    final pastille = size * 0.22;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            QrImageView(
              data: data,
              size: size,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
            ),
            Container(
              width: pastille,
              height: pastille,
              padding: EdgeInsets.all(pastille * 0.08),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(pastille * 0.22),
              ),
              child: Image.asset('assets/images/logo.png'),
            ),
          ],
        ),
      ),
    );
  }
}

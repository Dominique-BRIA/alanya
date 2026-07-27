import 'package:flutter/material.dart';
import '../../../theme/alanya_theme.dart';

class DialerScreen extends StatelessWidget {
  const DialerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14142A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Clavier", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.phone, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 60),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: TextField(
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 32, letterSpacing: 4),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: "",
              ),
              readOnly: true,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              children: [
                ..._buildKey("1"),
                ..._buildKey("2", sub: "ABC"),
                ..._buildKey("3", sub: "DEF"),
                ..._buildKey("4", sub: "GHI"),
                ..._buildKey("5", sub: "JKL"),
                ..._buildKey("6", sub: "MNO"),
                ..._buildKey("7", sub: "PQRS"),
                ..._buildKey("8", sub: "TUV"),
                ..._buildKey("9", sub: "WXYZ"),
                ..._buildKey("*"),
                ..._buildKey("0", sub: "+"),
                ..._buildKey("#"),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            child: Row(
              children: [
                Expanded(
                  child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    shape: const CircleBorder(),
                    onPressed: () {},
                    child: const Icon(Icons.person_add, color: Colors.black),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FloatingActionButton(
                    backgroundColor: Colors.green,
                    shape: const CircleBorder(),
                    onPressed: () {},
                    child: const Icon(Icons.phone, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildKey(String text, {String? sub}) {
    return [
      InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF14142A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(text, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              if (sub != null)
                Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
        ),
      ),
    ];
  }
}

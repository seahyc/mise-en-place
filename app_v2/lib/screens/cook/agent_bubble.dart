import 'package:flutter/material.dart';

/// Displays the voice agent's response text with an avatar.
class AgentBubble extends StatelessWidget {
  const AgentBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Agent avatar: 28px rounded-square with amber-to-orange gradient
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF9F0A), Color(0xFFFF6B2C)],
              ),
            ),
            alignment: Alignment.center,
            child: const Text(
              '\u266A', // music note
              style: TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xB3FFFFFF), // rgba(255,255,255,0.7)
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

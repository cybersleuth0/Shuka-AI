import 'dart:convert';
import 'package:http/http.dart' as http;

class AudioService {
  final String _baseUrl = 'http://10.0.2.16:8000'; // Replace with your actual IP

  Future<String> sendAudioToBackend(String audioBase64) async {
    final url = Uri.parse('$_baseUrl/chat');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'audio_base64': audioBase64}),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse['response'] as String;
      } else {
        throw Exception('Failed to load AI response: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to connect to the backend: $e');
    }
  }
}
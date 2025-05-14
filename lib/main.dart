import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;

import 'app_theme.dart';
import 'audio_service.dart';
import 'chat_bubble.dart';

enum RecordingState { idle, recording, processing, error }

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class AppState extends ChangeNotifier {
  List<ChatMessage> _messages = [];
  RecordingState _recordingState = RecordingState.idle;
  String? _errorMessage;
  Timer? _waveformTimer;
  double _currentAmplitude = 0.0;

  List<ChatMessage> get messages => _messages;
  RecordingState get recordingState => _recordingState;
  String? get errorMessage => _errorMessage;
  double get currentAmplitude => _currentAmplitude;

  void addMessage(ChatMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  void setRecordingState(RecordingState state) {
    _recordingState = state;
    notifyListeners();
  }

  void setErrorMessage(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  void startWaveformUpdates(AudioRecorder recorder) {
    _waveformTimer?.cancel();
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) async {
      final amp = await recorder.getAmplitude();
      _currentAmplitude = amp.current;
      notifyListeners();
    });
  }

  void stopWaveformUpdates() {
    _waveformTimer?.cancel();
    _currentAmplitude = 0.0;
    notifyListeners();
  }
}

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice AI Chat',
      theme: appTheme(context),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late AudioRecorder _audioRecorder;
  late AudioService _audioService;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _audioService = AudioService(); // Replace with your FastAPI backend IP

  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final appState = Provider.of<AppState>(context, listen: false);
    appState.setErrorMessage(null);

    if (await _audioRecorder.hasPermission()) {
      appState.setRecordingState(RecordingState.recording);
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.opus, sampleRate: 16000),
        path: '${(await getTemporaryDirectory()).path}/recording.webm',
      );
      appState.startWaveformUpdates(_audioRecorder);
    } else {
      appState.setErrorMessage("Microphone permission not granted.");
      appState.setRecordingState(RecordingState.error);
    }
  }

  Future<void> _stopRecording() async {
    final appState = Provider.of<AppState>(context, listen: false);
    appState.stopWaveformUpdates();
    appState.setRecordingState(RecordingState.processing);
    final path = await _audioRecorder.stop();

    if (path != null) {
      final audioFile = File(path);
      final bytes = await audioFile.readAsBytes();
      final base64Audio = base64Encode(bytes);

      appState.addMessage(
        ChatMessage(text: "User Audio (Processing...)", isUser: true),
      );

      try {
        final response = await _audioService.sendAudioToBackend(base64Audio);
        appState.addMessage(ChatMessage(text: response, isUser: false));
        appState.setRecordingState(RecordingState.idle);
      } catch (e) {
        appState.setErrorMessage("API Error: ${e.toString()}");
        appState.setRecordingState(RecordingState.error);
      } finally {
        await audioFile.delete();
      }
    } else {
      appState.setErrorMessage("Recording failed.");
      appState.setRecordingState(RecordingState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice AI Chat')),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: appState.messages.length,
                  itemBuilder: (context, index) {
                    final message = appState.messages[index];
                    return ChatBubble(
                      message: message.text,
                      isUserMessage: message.isUser,
                    );
                  },
                ),
              ),
              if (appState.recordingState == RecordingState.recording)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: FAProgressBar(
                    currentValue: appState.currentAmplitude * 100,
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                    progressColor: Theme.of(context).colorScheme.primary,
                    size: 10.0,
                    animatedDuration: const Duration(milliseconds: 50),
                  ),
                ),
              if (appState.recordingState == RecordingState.processing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: LinearProgressIndicator(),
                ),
              if (appState.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    appState.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: GestureDetector(
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressEnd: (_) => _stopRecording(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          appState.recordingState == RecordingState.recording
                              ? Colors.red
                              : Theme.of(context).colorScheme.primary,
                    ),
                    child: Icon(
                      appState.recordingState == RecordingState.recording
                          ? Icons.mic_none
                          : Icons.mic,
                      size: 48.0,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

ThemeData appTheme(BuildContext context) {
  final brightness = View.of(context).platformDispatcher.platformBrightness;
  return brightness == Brightness.dark ? darkTheme : lightTheme;
}

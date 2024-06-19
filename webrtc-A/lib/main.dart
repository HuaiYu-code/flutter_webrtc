import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: WebRTCPage(),
    );
  }
}

class WebRTCPage extends StatefulWidget {
  @override
  _WebRTCPageState createState() => _WebRTCPageState();
}

class _WebRTCPageState extends State<WebRTCPage> {
  late RTCPeerConnection _peerConnection;
  late MediaStream _localStream;
  late RTCVideoRenderer _localRenderer;
  late RTCVideoRenderer _remoteRenderer;
  late WebSocketChannel _channel;
  String senderID = '';
  String targetID = '';

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    final String serverUrl = 'ws://10.168.5.139:8080';
    _channel = WebSocketChannel.connect(Uri.parse(serverUrl));

    _channel.stream.listen((message) {
      print('Received message: $message');
      _handleMessage(message);
    }, onDone: () {
      print('WebSocket channel closed');
    }, onError: (error) {
      print('Error: $error');
    });
  }

  void _handleMessage(dynamic message) async {
    try {
      if (message is String) {
        final data = jsonDecode(message);
        senderID = data['id'] ?? '';
        targetID = data['sender'] ?? '';

        switch (data['type']) {
          case 'offer':
            final offer = RTCSessionDescription(data['offer']['sdp'], data['offer']['type']); // 修正此处
            await _peerConnection.setRemoteDescription(offer);
            final answer = await _peerConnection.createAnswer();
            await _peerConnection.setLocalDescription(answer);

            // 通过WebSocket发送answer给发起方
            _sendSignal(jsonEncode({
              'type': 'answer',
              'answer': sessionDescriptionToJson(answer),
              'target': targetID,
              'sender': senderID
            }));
            break;
          case 'ice_candidate':
            final candidate = RTCIceCandidate(
              data['candidate']['candidate'],
              data['candidate']['sdpMid'],
              data['candidate']['sdpMLineIndex'],
            );
            await _peerConnection.addCandidate(candidate);
            break;
        // ... 处理其他消息类型，如ICE候选
        }
      } else {
        print('Received message is not a String: $message');
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }

  Map<String, dynamic> sessionDescriptionToJson(RTCSessionDescription sessionDescription) {
    return {
      'type': sessionDescription.type,
      'sdp': sessionDescription.sdp,
    };
  }

  Map<String, dynamic> iceCandidateToJson(RTCIceCandidate candidate) {
    return {
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex ?? 0, // 默认值0，以防万一sdpMLineIndex为null
    };
  }


  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection.dispose();
    _channel.sink.close();
    super.dispose();
  }

  void _initRenderers() async {
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _createPeerConnection() async {
    final configuration = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };
    _peerConnection = await createPeerConnection(configuration);

    _peerConnection.onIceCandidate = (candidate) {
      _sendSignal(jsonEncode({
        'type': 'ice_candidate',
        'candidate': iceCandidateToJson(candidate),
        'target': targetID,
        'sender': senderID,
      }));
    };
    _peerConnection.onIceConnectionState = (state) {
      print('ICE Connection State: $state');
    };
    _peerConnection.onTrack = (event) {
      print('onTrack');
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };

    // 添加本地流的轨道到 PeerConnection
    if (_localStream != null) {
      for (var track in _localStream.getTracks()) {
        print('addTrack');
        _peerConnection.addTrack(track, _localStream);
      }
    }
  }

  void _createOffer() async {
    if (_peerConnection == null) {
      print('Error: _peerConnection is null');
      return;
    }
    try {
      final offer = await _peerConnection.createOffer({});
      await _peerConnection.setLocalDescription(offer);
      _sendSignal(json.encode({
        'type': 'offer',
        'offer': sessionDescriptionToJson(offer),
        'sender': senderID,
        'target': targetID,
      }));
    } catch (e) {
      print('Error during offer creation: $e');
    }
  }


  void _sendSignal(String message) {
    _channel.sink.add(message);
  }

  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    return statuses[Permission.camera]!.isGranted && statuses[Permission.microphone]!.isGranted;
  }

  Future<void> _getUserMedia() async {
    try {
      bool permissionsGranted = await _requestPermissions();
      if (!permissionsGranted) {
        print('Permissions not granted');
        return;
      }
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': {
          'facingMode': 'user',
        }
      };

      final MediaStream stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      setState(() {
        _localStream = stream;
        _localRenderer.srcObject = _localStream;
      });
    } catch (e) {
      print('Error getting user media: $e');
    }
  }

  void _startCall() async {
    _showInputDialog(context);
  }

  void  _showInputDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        TextEditingController _textFieldController = TextEditingController();
        return AlertDialog(
          title: Text('Enter Target ID'),
          content: TextField(
            controller: _textFieldController,
            decoration: InputDecoration(hintText: "Target ID"),
          ),
          actions: <Widget>[
            ElevatedButton(
              child: Text('CANCEL'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            ElevatedButton(
              child: Text('OK'),
              onPressed: () async {
                setState(() {
                  targetID = _textFieldController.text;
                });
                print('targetID:$targetID');
                Navigator.pop(context);
                await _getUserMedia();
                await _createPeerConnection();
                _createOffer();
                if (_localStream != null) {
                  setState(() {
                  });
                } else {
                  print('Failed to get local media stream.');
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WebRTC Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: RTCVideoView(_remoteRenderer),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed:  _startCall,
              child: Text('Start Call'),
            ),
            SizedBox(height: 20),
            Expanded(
                child: RTCVideoView(_localRenderer)
            ),
          ],
        ),
      ),
    );
  }
}

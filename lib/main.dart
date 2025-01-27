// ignore_for_file: unused_import

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:cool_alert/cool_alert.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  initializeDateFormatting().then(
    (_) => runApp(
      const SimpleChat(),
    )
  );
}

class SimpleChat extends StatelessWidget {
  const SimpleChat({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'chat'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  List<types.Message> _messaggi = [];
  final Object _usersId = {'Nikolas':'yhw34i87hy7e8rwchb8iweb9f734b97', 'Monia':'yhw34i87hy7e8rwc4yfgweb9f734b97', 'Matteo': '4'};
  
  final _user = const types.User(
    id: 'yhw34i87hy7e8rwchb8iweb9f734b97',
    firstName: 'Nikolas',
    lastName: 'Panterini'
  );


  //
  late IO.Socket socket;
  //final StreamController<String> _streamController = StreamController<String>();    STREAMCONTROLLER
  //Stream<String> get messagesStream => _streamController.stream;    STREAMCONTROLLER
  
  @override
  void dispose() {
    socket.disconnect();

    //_streamController.close();  STREAMCONTROLLER
    super.dispose();
  }

 void sendMessage(String message) {
    socket.emit('sendMessage', message);
  }
  //

  @override
  void initState() {
    super.initState();
    _loadMessages();

    
    socket = IO.io("http://192.168.141.102:3000", <String, dynamic> {   //IP DEL SERVER
      'transports': ['websocket',]
    });

    socket.on('connect', (_) {
      if(mounted){
        _showAlert(context, "Connessione", "ora sei connesso");
      }
    });

    socket.on('message', (data) {
      //_streamController.add(data);    STREAMCONTROLLER      

      final message = data;
      final textMessage = types.TextMessage(
        author: types.User.fromJson(message['author']),
        id: message['id'],
        text: message['text'],
        createdAt: message['createdAt'],
      );

      //if(_messaggi.last.id == message['id'])
      if(!_messaggi.any((msg) => msg.id == message['id'])){
        setState(() {
            _addMessage(textMessage);   
        });
      }   
    });
  }

  Future<String> _getFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/messagi.json';
  }

  void _loadMessages() async {
    final path = await _getFilePath();
    final file = File(path);
    if(await file.exists()) {
      final jsonContent = file.readAsStringSync();
      final jsonList = (jsonDecode(jsonContent) as List).map((e) => types.Message.fromJson(e as Map<String,dynamic>)).toList();
      setState(() {
        _messaggi = jsonList;
      });
    }
  }

  void _showAlert(BuildContext context, String title, String content) {
    CoolAlert.show(
      context: context,
      type: CoolAlertType.success,
      title: title,
      text: content,
      loopAnimation: false,
    );
  }

  void _handlePreviewDataFetched(
    types.TextMessage message,
    types.PreviewData previewData
  ) {
    final index = _messaggi.indexWhere((element) => element.id == message.id);
    final updateMessage = (_messaggi[index] as types.TextMessage).copyWith(
      previewData: previewData,
    );

    setState(() {
      _messaggi[index] = updateMessage;
    });
  }

  void _handleSendPressed(types.PartialText message){
    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: const Uuid().v4(),
      text: message.text
    );
    
    if(socket.connected){
      socket.emit("sendMessage", textMessage);
    }

    _addMessage(textMessage);
  }

  void _addMessage(types.Message message) async {
    final filepath = await _getFilePath();
    final file = File(filepath);
    setState(() {
      _messaggi.insert(0, message);
    });
    final jsonString = jsonEncode(_messaggi);
    await file.writeAsString(jsonString);
  }

  Future<File> loadFile() async {
    final filePath = await _getFilePath();
    return File(filePath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Chat(
        messages: _messaggi,
        onPreviewDataFetched: _handlePreviewDataFetched,
        onSendPressed: _handleSendPressed,
        showUserAvatars: true,
        showUserNames: true,
        user: _user,
        theme: const DefaultChatTheme(
          seenIcon: Text(
            'read',
            style: TextStyle(
              fontSize: 10.0,
            ),
          ),
        ),
      ),
    );
  }
}
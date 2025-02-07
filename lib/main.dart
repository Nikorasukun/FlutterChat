// ignore_for_file: unused_import

//chat dependencies
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

//login dependencies
import 'package:flutter_signin_button/flutter_signin_button.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

//stati dell'applicazione
enum Status{
  login,
  inChat
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  initializeDateFormatting().then(
    (_) => runApp(
      const SimpleChat(),
    )
  );
}

class SimpleChat extends StatelessWidget {
  const SimpleChat({super.key});

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
  Status appStatus = Status.login;

  List<types.Message> _messaggi = [];
  dynamic _user;

  late IO.Socket socket;
  
  @override
  void dispose() {
    socket.disconnect();
    super.dispose();
  }

 void sendMessage(String message) {
    socket.emit('sendMessage', message);
  }
  

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loggati();
    
    socket = IO.io("http://192.168.1.23:3000", <String, dynamic> {   //IP DEL SERVER
      'transports': ['websocket',]
    });
    
    socket.on('connect', (_) {
      if(mounted){
        //_showAlert(context, "Connessione", "ora sei connesso");
      }
    });

    socket.on('message', (data) {  
      final message = data;
      final textMessage = types.TextMessage(
        author: types.User.fromJson(message['author']),
        id: message['id'],
        text: message['text'],
        createdAt: message['createdAt'],
      );

      if(!_messaggi.any((msg) => msg.id == message['id'])){
        setState(() {
            _addMessage(textMessage);   
        });
      }
    });
  }

  Future<void> _loggati() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if(googleUser == null) {
        return;
      }

      final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken
      );

      UserCredential userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);

      User? user = userCredential.user;
      _user = null;
      _user = types.User(id: user!.uid, firstName: user.displayName);
      if (/*user != null USELESS*/true) {
        setState(() {
          appStatus = Status.inChat;
        });
      }
    } catch(e) {
      if(mounted){
        _showAlert(context, "Login Error", "Il login con Google ha fallito, ritenta. [[$e]]");
      }
    }
  }

  Future<void> _logout() async {
    try {
      await GoogleSignIn()
        .signOut();
      setState(() {
        appStatus = Status.login;
      });
    } catch(e) {
      if(mounted){
        _showAlert(context, "Logout Error", "Si è verificato un errore con il logout, ritenta. ($e)");
      }
    }
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
    
    if(textMessage.text.startsWith("/logout") && appStatus == Status.inChat) {
      setState(() {
        _logout();
      });
    }
    else
    {
      if(socket.connected && textMessage.text.startsWith("/room")) {      
      socket.emit('join-room', textMessage.text.substring(5));
      }
      else
      {
        if(socket.connected){
          socket.emit("sendMessage", textMessage);
          _addMessage(textMessage);
        }
      }
    }    
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

  Widget _buildBody() {
    switch(appStatus){
      case Status.inChat:
        return Chat(
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
        );
      
      case Status.login:
        return Center(
        child: Column(          
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SignInButton(Buttons.Google, onPressed: _loggati),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody()
    );
  }
}
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
enum Status { login, inChat, ipAssigning }

//il main dell'applicazione
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //con questo comando si inizializza firebase per la connessione con google
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  //fatto per le date e i caratteri strani, non implementato
  initializeDateFormatting().then((_) => runApp(
        const SimpleChat(),
      ));
}

//è qui perché sì, Flutter lo vuole
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
      home: const MyHomePage(title: 'NM Chat'),
    );
  }
}

//è qui perché sì, Flutter lo vuole
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

//vera e propria application
class _MyHomePageState extends State<MyHomePage> {
  //enum che decreterà dinamicamente lo stato della mia applicazione
  Status appStatus = Status.ipAssigning;

  //l'ip del server
  TextEditingController txtController = TextEditingController();
  late String serverIp;

  //lista messaggi di appoggio json
  List<types.Message> _messaggi = [];

  //lo user identificativo, sarà in ogni messaggio
  dynamic _user;

  //dichiarazione ritardata del socket
  late IO.Socket socket;

  //override del dispose per far sì che non resti aperto il socket post chiusura app
  @override
  void dispose() {
    super.dispose();
    socket.disconnect();
  }

  //emit per far partire il messaggio verso il server
  void sendMessage(String message) {
    socket.emit('sendMessage', message);
  }

  //override initState, metodo che parte a inizio app, veramente importante
  @override
  void initState() {
    super.initState();

    //metodo per caricare i messaggi da json
    _loadMessages();

    //creazione socket con ip del server, da automatizzare
    socket = IO.io("http://0.0.0.0:3000", <String, dynamic>{
      //IP DEL SERVER
      'transports': [
        'websocket',
      ]
    });
  }

  //metodo copia incollato da veneti per login google
  Future<void> _loggati() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);

      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      User? user = userCredential.user;
      _user = null;
      _user = types.User(id: user!.uid, firstName: user.displayName);
      if (/*user != null USELESS*/ true) {
        setState(() {
          //cambio lo status dell'app, esco da login
          appStatus = Status.inChat;
        });
      }
    } catch (e) {
      if (mounted) {
        //ipotetico errore
        _showAlert(context, "Login Error",
            "Il login con Google ha fallito, ritenta. [[$e]]");
      }
    }
  }

  //implementazione forma di logout dall'account
  Future<void> _logout() async {
    try {
      await GoogleSignIn().signOut();
      setState(() {
        //nel caso vada a buon fine, torno a login
        appStatus = Status.login;
      });
    } catch (e) {
      if (mounted) {
        //ipotetico errore
        _showAlert(context, "Logout Error",
            "Si è verificato un errore con il logout, ritenta. ($e)");
      }
    }
  }

  //ottenere la directory per file json
  Future<String> _getFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/messagi.json';
  }

  //carico i messaggi da json a cgat
  void _loadMessages() async {
    final path = await _getFilePath();
    final file = File(path);
    if (await file.exists()) {
      final jsonContent = file.readAsStringSync();
      final jsonList = (jsonDecode(jsonContent) as List)
          .map((e) => types.Message.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _messaggi = jsonList;
      });
    }
  }

  //metodo per mostrare alert
  void _showAlert(BuildContext context, String title, String content) {
    CoolAlert.show(
      context: context,
      type: CoolAlertType.success,
      title: title,
      text: content,
      loopAnimation: false,
    );
  }

  //metodo tutto copiato da Veneti, non so propriamente cosa faccia
  void _handlePreviewDataFetched(
    types.TextMessage message, types.PreviewData previewData) {
    final index = _messaggi.indexWhere((element) => element.id == message.id);
    final updateMessage = (_messaggi[index] as types.TextMessage).copyWith(
      previewData: previewData,
    );

    setState(() {
      _messaggi[index] = updateMessage;
    });
  }

  //si triggera quando clicchi il tasto per spedire il messaggio
  void _handleSendPressed(types.PartialText message) {
    final textMessage = types.TextMessage(
        author: _user,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: const Uuid().v4(), //id univoco per ogni messaggio
        text: message.text);

    //funzionalità di logout tramite comando
    if (textMessage.text.startsWith("/") /*&& appStatus == Status.inChat*/) {
      _commands(textMessage.text.substring(1).split(' ')[0], 
                textMessage.text.substring(1,5) == "room" ?
                textMessage.text.substring(1).split(' ')[1] : "");
    }
    else {
      if (socket.connected) {
        //normale emissione di messaggio
        socket.emit("sendMessage", textMessage);
        _addMessage(textMessage);
      }
    }
  }

  void _commands(command, params) {
    switch (command) {
      case "logout":
        setState(() {
          //chiama semplicemente il metodo descritto in precedenza
          _logout();
        });
        break;

      case "ipassign":
        setState(() {
          appStatus = Status.ipAssigning;
          txtController.text = "";
        });
        break;

      case "room":
        socket.emit('join-room', params);
        break;

      case "help":
        _showAlert(context, "command list:", "command: logout\nparams: none\ndescription: returns to the login screen.\n\ncommand: ipassign\nparams: none\ndescription: returns to the ip assigning screen.\n\ncommand: room\nparams: roomName\ndescription: it makes you connect to a specified room.");
        break;

      default:
        _showAlert(context, "command not recognized", 'Command: $command, Params: $params');
        break;
    }
  }

  //aggiunta di messaggi all'interno del json + ricarica chat
  void _addMessage(types.Message message) async {
    final filepath = await _getFilePath();
    final file = File(filepath);
    setState(() {
      _messaggi.insert(0, message);
    });
    final jsonString = jsonEncode(_messaggi);
    await file.writeAsString(jsonString);
  }

  //autoesplicativo
  Future<File> loadFile() async {
    final filePath = await _getFilePath();
    return File(filePath);
  }

  //metodo per l'assegnazione dinamica dell'ip server
  void _ipAssign() {
    serverIp = txtController.text;
    socket = IO.io('http://$serverIp:3000', <String, dynamic>{
      'transports': [
        'websocket',
      ]
    });

    socket.on('connect', (_) {
      setState(() {
        if (mounted) {
          _showAlert(context, "Connessione", "ora sei connesso");
        }
      });
    });

    socket.on('message', (data) {
      setState(() {
        //creazione messaggio fittizio, dava errore se tenevo lo stesso
        final message = data;
        final textMessage = types.TextMessage(
          author: types.User.fromJson(message['author']),
          id: message['id'],
          text: message['text'],
          createdAt: message['createdAt'],
        );

        //controllo per non impostare nella chat anche i messaggi che io stesso ho spedito
        if (!_messaggi.any((msg) => msg.id == message['id'])) {
          setState(() {
            //metodo che effettivamente inserirà il messaggio nel json
            _addMessage(textMessage);
          });
        }
      });
    });

    _loggati();
  }

  //metodo per la creazione dinamica del body in base allo stato
  Widget _buildBody() {
    switch (appStatus) {
      //per settare l'ip iniziale
      case Status.ipAssigning:
        return Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 225, height: 75, child: TextField(controller: txtController, onEditingComplete: _ipAssign))
          ],
        ));

      //se non loggato ancora
      case Status.login:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SignInButton(Buttons.Google, onPressed: _loggati),
            ],
          ),
        );

      //se superato il login
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
    }
  }

  //effettiva app, piccola perché il body è nel metodo
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _buildBody(),
      drawer: Drawer(
        child: ListView(
          children: [
            ListTile(
              title: const Text('Back to login'),
              onTap: () {
                setState(() {if(appStatus == Status.inChat) {_logout();};});
              },
            ),
            ListTile(
              title: const Text('Back to ip assigning'),
              onTap: () {
                setState(() {if(appStatus == Status.login || appStatus == Status.inChat) {appStatus = Status.ipAssigning; txtController.text = "";}});
              },
            ),
            ListTile(
              title: const Text('help'),
              onTap: () {
                setState(() {_showAlert(context, "How does it work?", "To use the <Back to Login> button you need to have assigned an ip.\n\nTo use the <Back to ip assigning> button you can be wherever you want.\n\nTo use the <help> button... you just used it..");});
              },
            ),
          ],
        ),
      ),
    );
  }
}

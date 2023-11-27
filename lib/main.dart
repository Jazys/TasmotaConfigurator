import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webview_plugin/flutter_webview_plugin.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:plugin_wifi_connect/plugin_wifi_connect.dart';
import 'package:http/http.dart' as http;
import 'package:simple_wifi_info/wifi_info.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluttertoast/fluttertoast.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tasmota Configurator',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: WifiScannerPage(),
    );
  }
}

class WifiScannerPage extends StatefulWidget {
  @override
  _WifiScannerPageState createState() => _WifiScannerPageState();
}

class _WifiScannerPageState extends State<WifiScannerPage> {
  late TextEditingController _passwordController;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  String _ipAddress   = '192.168.4.1';
  ScanResult? scanResult;
  List<String> _wifiList = [];
  String currentSSID ="";
  String wifiPassword ="";
  String tasmotaSSID  ="";
  String newIpAddress ="";
  int TimeToWaitAfterPassword=15;
  int TimeToWaitAfterGetNewIP=5;
  int TimeToWaitAfterWifiDisconnected=5;


  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController(text: '');
    _checkWifi();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    try {
      final result = await BarcodeScanner.scan();
      setState(() {
        scanResult = result;
        var key=extractWiFiKey(scanResult!.rawContent!);
        print(key);
        setState((){
          wifiPassword=key;
        });
        }
      );
    } on PlatformException catch (e) {
      setState(() {
        scanResult = ScanResult(
          rawContent: e.code == BarcodeScanner.cameraAccessDenied
              ? 'The user did not grant the camera permission!'
              : 'Unknown error: $e',
        );
      });
    }
  }

  String extractWiFiKey(String qrCodeData) {
    // Vérifie si la chaîne commence par 'WIFI:'
    if (qrCodeData.startsWith('WIFI:')) {
      // Sépare les paramètres par ';'
      List<String> params = qrCodeData.split(';');

      // Parcourt les paramètres pour trouver la clé Wi-Fi (motif 'P:')
      for (String param in params) {
        if (param.startsWith('P:')) {
          // Extrait la clé Wi-Fi
          return param.substring(2); // Ignorer le préfixe 'P:'
        }
      }
    }
    return ''; // Retourne une chaîne vide si aucune clé n'est trouvée
  }


    Future<void> _checkWifi() async {
    var wifiStatus = await Connectivity().checkConnectivity();
    if (wifiStatus == ConnectivityResult.wifi) {
      _getWifiList();
    } else {
    }
  }

  Future<void> _getWifiList() async {
    var status = await Permission.location.request();
    if (status.isGranted) {
      await WiFiScan.instance.startScan();
      var wifiList = await WiFiScan.instance.getScannedResults();
      setState(() {
        _wifiList = wifiList.map((e) => e.ssid).toList();
      });
      List<String> filteredWifiList = _wifiList.where((wifiName) => wifiName.contains('tasmota-')).toList();
      this.tasmotaSSID=filteredWifiList[0];

    }
  }

  Future<void> _connectToWifiAndConfigure(String ssid) async {

    var status = await Permission.location.request();
    if (status.isGranted) {
      try {
        var currentSSIDInfo = await WifiInfo().getWifiInfo();
        currentSSID = currentSSIDInfo!.ssid!;
        var connectTasmota= await PluginWifiConnect.connect(ssid);
        var tasmotaInfoSSID= await WifiInfo().getWifiInfo();
        print(tasmotaInfoSSID!.bssid);
        await _sendGetRequest('http://192.168.4.1/wi?s1=${currentSSID}&p1=${wifiPassword}&save=');
        showToast("Connection is processing !!!");
        await Future.delayed(Duration(seconds: TimeToWaitAfterPassword));
        await _sendGetRequest('http://192.168.4.1');
        showToast("Get new IP !!!");
        await Future.delayed(Duration(seconds: TimeToWaitAfterGetNewIP));
        await PluginWifiConnect.disconnect();
        await Future.delayed(Duration(seconds: TimeToWaitAfterWifiDisconnected));
        showToast("Now you can access to Tasmota with configurated IP");
      } catch (e) {
        // Gestion de l'erreur de connexion
      }
    } else {
      // Gestion du refus de la permission
    }
  }

  Future<void> _sendGetRequest(url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        //print('Requête GET réussie');
        //print('Réponse : ${response.body}');

        if (response.body.contains('Connect failed')) {
          print('Le texte "Connect Failed" est présent dans la réponse.');
        } else {
          print('Le texte "Connect Failed" n\'est pas présent dans la réponse.');
        }

        if (response.body.contains('Redirecting to new')) {
          var ipAdr=extractIPAddress(response.body);
          print(ipAdr);
          setState(() {
            newIpAddress =ipAdr;
          });
        }
      } else {
        showToast("Unable to request Default Tasmota Config");
        print('Échec de la requête GET avec le code d\'état : ${response.statusCode}');
      }
    } catch (e) {
      // Erreur lors de la requête
      print('Erreur lors de la requête GET : $e');
    }
  }

  Future<void> _launchInBrowser() async {
    final Uri toLaunch =
    Uri(scheme: 'http', host: newIpAddress, path: '/');
    if (!await launchUrl(
      toLaunch,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Could not launch $toLaunch');
    }
  }

  String extractIPAddress(String htmlBody) {
    const searchString = 'Redirecting to new';
    int startIndex = htmlBody.indexOf(searchString);
    print(startIndex);
    if (startIndex != -1) {
      startIndex += searchString.length;
      String remainingString = htmlBody.substring(startIndex);

      RegExp regExp = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
      Match? match = regExp.firstMatch(remainingString);

      if (match != null) {
        return match.group(0) ?? '';
      }
    }

    return '0.0.0.0';
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tasmota Configurator'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Available Wifi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _wifiList.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_wifiList[index])
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Wifi Key: $wifiPassword', // Afficher la clé WPA
              style: TextStyle(fontSize: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: () {
                    // Logique pour scanner le QR code
                    _checkWifi();
                  },
                  child: Text('Refresh wifi list'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Logique pour scanner le QR code
                    _scan();
                  },
                  child: Text('Scan Wifi Password'),
                ),
                SizedBox(height: 8), // Espacement entre les boutons
                ElevatedButton(
                  onPressed: () {
                    // Logique pour entrer la clé WPA
                    _showPasswordDialog(context);
                  },
                  child: Text('Enter Wifi Password'),
                ),
                SizedBox(height: 8), // Espacement entre les boutons
                ElevatedButton(
                  onPressed: () {
                    // Logique pour configurer
                    _connectToWifiAndConfigure(tasmotaSSID);
                  },
                  child: Text('Configure Tasmota'),
                ),
                SizedBox(height: 8), // Espacement entre les boutons
                ElevatedButton(
                  onPressed: () {
                    // Logique pour configurer
                    _launchInBrowser();
                  },
                  child: Text('Webpage access'),
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'New tasmota IP : $newIpAddress', // Afficher la clé WPA
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  void showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT, // Durée du toast (courte ou longue)
      gravity: ToastGravity.BOTTOM, // Position du toast sur l'écran (ex : en bas)
      timeInSecForIosWeb: 1, // Durée spécifique pour iOS et Web
      backgroundColor: Colors.grey, // Couleur de fond du toast
      textColor: Colors.white, // Couleur du texte du toast
      fontSize: 16.0, // Taille de police du toast
    );
  }

  Future<void> _showPasswordDialog(BuildContext context) async {
    String enteredPassword = ''; // Variable pour stocker le mot de passe entré

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Enter Password '),
          content: TextField(
            controller: _passwordController,
            obscureText: false, // Masquer le texte pour afficher les caractères du mot de passe
            onChanged: (value) {
              setState(() {
                wifiPassword=value;
              });
            },
            decoration: InputDecoration(hintText: 'Password'),
          ),
          actions: <Widget>[
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Fermer la boîte de dialogue
                // Utilisez enteredPassword où vous en avez besoin dans votre application
                print('Mot de passe saisi : $wifiPassword');
              },
              child: Text('Ok'),
            ),
          ],
        );
      },
    );
  }
}


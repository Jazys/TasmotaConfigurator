import 'dart:io';

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
import 'package:multicast_dns/multicast_dns.dart';
import 'package:flutter_nsd/flutter_nsd.dart';

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
  List<String> _wifiListWithoutTasmota = [];
  String currentSSID ="";
  String wifiPassword ="";
  String tasmotaSSID  ="";
  String newIpAddress ="";
  int TimeToWaitAfterPassword=15;
  int TimeToWaitAfterGetNewIP=5;
  int TimeToWaitAfterWifiDisconnected=5;
  bool _isConfiguring = false;
  String selectedKindOfDevice="Tasmota";


  final flutterNsd = FlutterNsd();
  final services = <NsdServiceInfo>[];
  bool initialStart = true;
  bool _scanning = false;


  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController(text: '');
    _checkWifi();
    flutterNsd.stream.listen(
          (NsdServiceInfo service) async {
            print('Discovered service name: ${service.name}');
            if(service.name == tasmotaSSID && _isConfiguring) {
              //newIpAddress=service.hostname!;
              newIpAddress=await resolveHostnameToIPv4(service.hostname!);
              showToast('Vous pouvez accéder à la page via ${newIpAddress} ');
              Navigator.of(context, rootNavigator: true).pop('dialog');
              setState(() {
                _isConfiguring = false; // Arrêtez le chargement une fois terminé
              });
              stopDiscovery();
            }
      },
      onError: (e) async {
        if (e is NsdError) {
          if (e.errorCode == NsdErrorCode.startDiscoveryFailed &&
              initialStart) {
            await stopDiscovery();
          } else if (e.errorCode == NsdErrorCode.discoveryStopped &&
              initialStart) {
            initialStart = false;
            await startDiscovery();
          }
        }
      },
    );
  }

  Future<String> resolveHostnameToIPv4(String hostname) async {
    try {
      final result = await InternetAddress.lookup(hostname);
      final ipv4Addresses = result.where((address) => address.type == InternetAddressType.IPv4);

      if (ipv4Addresses.isNotEmpty) {
        print(ipv4Addresses.first.address);
        return ipv4Addresses.first.address;
      } else {
        return 'Aucune adresse IPv4 trouvée pour $hostname.';
      }
    } catch (error) {
      return 'Erreur de connexion réseau : $error';
    }
  }

  Future<void> startDiscovery() async {
    if (_scanning) return;

    setState(() {
      services.clear();
      _scanning = true;
    });
    await flutterNsd.discoverServices('_http._tcp.');
  }

  Future<void> stopDiscovery() async {
    if (!_scanning) return;

    setState(() {
      services.clear();
      _scanning = false;
    });
    flutterNsd.stopDiscovery();
  }

  void startTimer() {
    const timeout = Duration(seconds: 30); // Définissez la durée souhaitée
    Timer(timeout, () {
      setState(() {

        if(_isConfiguring)
          showToast("Recommencer l'opération ! Nom du réseau ou mot de passe incorrect");

        _isConfiguring = false;

      });
    });
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
    //discoverServices();
    //startDiscovery();
  }

  Future<void> _getWifiList() async {
    var status = await Permission.location.request();
    if (status.isGranted) {
      await WiFiScan.instance.startScan();
      var wifiList = await WiFiScan.instance.getScannedResults();
      setState(() {
        _wifiList = wifiList.map((e) => e.ssid).toList();
        _wifiListWithoutTasmota = wifiList.map((e) => e.ssid).toList();

        _wifiList = _wifiList.where((wifiName) => wifiName.contains("${selectedKindOfDevice.toLowerCase()}-")).toList();

        if(_wifiList.isNotEmpty) tasmotaSSID=_wifiList[0];

        _wifiListWithoutTasmota = _wifiListWithoutTasmota.where((wifiName) => !_wifiListWithoutTasmota.contains('tasmota-')).toList();

      });


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
        setState(() {
          _isConfiguring = true;
        });

        showDialog(
          context: context,
          barrierDismissible: false, // L'utilisateur ne peut pas fermer le dialogue
          builder: (BuildContext context) {
            return Dialog(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 24),
                    Text("Config in progress ...."),
                  ],
                ),
              ),
            );
          },
        );

        if( selectedKindOfDevice.toLowerCase() == "tasmota") {
          await _sendGetRequest(
              'http://192.168.4.1/wi?s1=${currentSSID}&p1=${wifiPassword}&save=');
          showToast("Connection is processing !!!");
          await Future.delayed(Duration(seconds: TimeToWaitAfterPassword));
          await _sendGetRequest('http://192.168.4.1');
          showToast("Get new IP ${newIpAddress} !!!");
          await Future.delayed(Duration(seconds: TimeToWaitAfterGetNewIP));
          await PluginWifiConnect.disconnect();
          await Future.delayed(
              Duration(seconds: TimeToWaitAfterWifiDisconnected));
          Navigator.of(context, rootNavigator: true).pop('dialog');
          setState(() {
            _isConfiguring = false; // Arrêtez le chargement une fois terminé
          });
          showToast("Now you can access to Tasmota with configurated IP");
        }else if(selectedKindOfDevice.toLowerCase() == "esphome"){
          await _sendGetRequest(
              'http://192.168.4.1/wifisave?ssid=${currentSSID}&psk=${wifiPassword}');
          showToast("Connection is processing !!!");
          await Future.delayed(Duration(milliseconds: 50));
          await _sendGetRequest('http://192.168.4.1/?save');
          await Future.delayed(Duration(seconds: 2));
          await PluginWifiConnect.disconnect();
          await Future.delayed(
              Duration(seconds: TimeToWaitAfterWifiDisconnected));
          startDiscovery();
          startTimer();
        }

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
      if (response.statusCode == 200 || response.statusCode == 302) {
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

  Future<void> discoverServices() async {
    final MDnsClient client = MDnsClient();
    print("tototo");
    await client.start();

    // Change '_esphomelib._tcp.local' to the service type you are looking for
    await for (PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('test'))) {
      await for (SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName))) {
        print('Found device at ${srv.target}:${srv.port}');
      }
    }
    client.stop();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tasmota Configurator'),
      ),
      body: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                "Notice:",
                style: TextStyle(fontSize: 16,fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                "Please, shutdown all Tasmota device you don't want to configure.\nFollow step 1 to 4 to configure your device in your wifi network."
                    "\nSelected network are the same use by our phone.\n If IP is already blank, please retry all steps",
                style: TextStyle(fontSize: 15),
              ),
            ),
            SizedBox(height: 16.0), // Ajoutez un espace vertical ici
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Available ${selectedKindOfDevice} Device ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            // Ajout de la logique pour gérer une liste vide
            _wifiList.isNotEmpty
                ? Column(
              children: _wifiList.map((wifiName) {
                return ListTile(
                  title: Text(wifiName),
                );
              }).toList(),
            )
                : Text("No devices found"),
            SizedBox(height: 16.0), // Ajoutez un espace vertical ici
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Selected Wifi: $currentSSID',
                style: TextStyle(fontSize: 16),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Wifi Key: $wifiPassword',
                style: TextStyle(fontSize: 16),
              ),
            ),
            // ... Suite du code ...
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: () {_showChoicKindDeviceeDialog(context);},
                    child: Text('0- Select Device type (default Tasmota)'),
                  ),
                  ElevatedButton(
                    onPressed: () {_checkWifi(); startDiscovery();},
                    child: Text('1- Refresh available wifi device'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      var currentSSIDInfo = await WifiInfo().getWifiInfo();
                      setState(() {
                        currentSSID = currentSSIDInfo!.ssid!;
                      });
                      stopDiscovery();
                    },
                    child: Text('2- Refresh your current Wifi'),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => _showPasswordDialog(context),
                    child: Text('3 -Enter Wifi Password'),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      _connectToWifiAndConfigure(tasmotaSSID);
                    },
                    child: Text('4- Configure Automatically $selectedKindOfDevice'),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _launchInBrowser,
                    child: Text('5- Webpage access'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'New tasmota IP : $newIpAddress',
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

  Future<void> _showChoicKindDeviceeDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text('Choose your device Type:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  selectedKindOfDevice = 'Tasmota';
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tasmota', style: TextStyle(fontSize: 18)),
                  Icon(Icons.flash_on),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  selectedKindOfDevice = 'ESPHome';
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('ESPHome', style: TextStyle(fontSize: 18)),
                  Icon(Icons.home),
                ],
              ),
            ),
          ],
        );
      },
    );
  }


}


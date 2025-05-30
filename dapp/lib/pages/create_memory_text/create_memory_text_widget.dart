import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '/backend/api_requests/api_calls.dart';
import '/flutter_flow/custom_functions.dart';
import '/config/starknet_config.dart';
import 'package:starknet_provider/starknet_provider.dart';
import 'package:starknet/starknet.dart' show Felt;
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/starknet_utils.dart';
import 'create_memory_text_model.dart';
export 'create_memory_text_model.dart';

class CreateMemoryTextWidget extends StatefulWidget {
  const CreateMemoryTextWidget({super.key});

  static String routeName = 'CreateMemoryText';
  static String routePath = '/createMemoryText';

  @override
  State<CreateMemoryTextWidget> createState() => _CreateMemoryTextWidgetState();
}

class _CreateMemoryTextWidgetState extends State<CreateMemoryTextWidget> {
  late CreateMemoryTextModel _model;
  String _unlockType = 'timestamp'; // 'timestamp' o 'heris'
  int _heirsCount = 0;
  int _minConsensus = 0;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => CreateMemoryTextModel());

    _model.memoryNameTextController ??= TextEditingController();
    _model.memoryNameFocusNode ??= FocusNode();

    _model.memoryDescriptionTextController ??= TextEditingController();
    _model.memoryDescriptionFocusNode ??= FocusNode();

    _model.secretTextTextController ??= TextEditingController();
    _model.secretTextFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<void> _uploadToIPFS() async {
    try {
      final secretText = _model.secretTextTextController.text;
      if (secretText.isEmpty) {
        throw Exception('Secret text is required');
      }

      // Convertir el texto a base64
      final base64Text = base64Encode(utf8.encode(secretText));

      // Llamar a la API de IPFS
      final response = await IPFSUploaderCall.call(
        base64File: base64Text,
      );

      if (!response.succeeded) {
        throw Exception('Failed to upload to IPFS');
      }

      print('✅ Upload successful');
      print('📝 IPFS CID: ${IPFSUploaderCall.ipfsCID(response.jsonBody)}');
      print('🔑 File Secret: ${IPFSUploaderCall.fileSecret(response.jsonBody)}');
      print('🔒 Hash Commit: ${IPFSUploaderCall.hashCommit(response.jsonBody)}');

      if (_unlockType == 'timestamp') {
        await _handleTimestampUnlock(response);
      } else {
        // TODO: Manejar el caso de herederos
      }
    } catch (e) {
      print('❌ Error uploading to IPFS: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Felt _stringToFelt(String str) {
    // Para strings cortos, convertir directamente a Felt
    try {
      // Si el string es corto (menos de 31 caracteres), usar directamente
      if (str.length <= 31) {
        final bytes = utf8.encode(str);
        final hexString = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        return Felt.fromHexString('0x$hexString');
      } else {
        // Para strings largos, truncar y convertir
        final truncated = str.substring(0, 31);
        final bytes = utf8.encode(truncated);
        final hexString = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        return Felt.fromHexString('0x$hexString');
      }
    } catch (e) {
      print('❌ Error en _stringToFelt: $e');
      // Fallback: usar hash del string
      return Felt.fromInt(str.hashCode.abs() % 1000000);
    }
  }

  Future<void> _handleTimestampUnlock(ApiCallResponse ipfsResponse) async {
    try {
      // 1. Obtener la cuenta del usuario
      final account = await StarknetConfig.getAccount();
      
      // 2. Obtener la wallet del usuario para la public key (ya la tenemos en account.address)
      final publicKey = account.accountAddress.toHexString();

      // 3. Cifrar el secret con la public key
      final fileSecret = IPFSUploaderCall.fileSecret(ipfsResponse.jsonBody);
      if (fileSecret == null) {
        throw Exception('No se pudo obtener el file secret de IPFS');
      }

      final encryptedSecret = encryptWithRSA(fileSecret, publicKey);
      print('🔐 Secret cifrado: $encryptedSecret');

      // 4. Preparar los datos para el contrato
      final cid = IPFSUploaderCall.ipfsCID(ipfsResponse.jsonBody);
      final hashCommit = IPFSUploaderCall.hashCommit(ipfsResponse.jsonBody);
      
      if (cid == null || hashCommit == null) {
        throw Exception('No se pudieron obtener los datos necesarios de IPFS');
      }

      final memoryName = _model.memoryNameTextController.text;
      final unlockTimestamp = _model.datePicked?.millisecondsSinceEpoch != null 
          ? (_model.datePicked!.millisecondsSinceEpoch ~/ 1000) 
          : (DateTime.now().millisecondsSinceEpoch ~/ 1000);

      final selector = await StarknetUtils.getFunctionSelector(
        account.provider as JsonRpcProvider, // StarknetUtils espera un JsonRpcProvider
        StarknetConfig.contractAddress,
        'save_metadata',
      );

      // 5. Llamar al método save_metadata del contrato
      print('📝 Enviando datos al contrato:');
      print('  - Hash Commit: $hashCommit (length: ${hashCommit.length})');
      print('  - CID: $cid (length: ${cid.length})');
      print('  - Encrypted Secret: $encryptedSecret (length: ${encryptedSecret.length})');
      print('  - Timestamp: $unlockTimestamp');
      print('  - Memory Name: $memoryName (length: ${memoryName.length})');
      
      // Debug: probar la conversión de cada string individualmente
      print('🔍 Testing string conversions:');
      try {
        final hashCommitFelt = _stringToFelt(hashCommit);
        print('  - Hash Commit felt: $hashCommitFelt');
      } catch (e) {
        print('  - Error with Hash Commit: $e');
      }
      
      try {
        final encryptedSecretFelt = _stringToFelt(encryptedSecret);
        print('  - Encrypted Secret felt: $encryptedSecretFelt');
      } catch (e) {
        print('  - Error with Encrypted Secret: $e');
      }
      
      try {
        final cidFelt = _stringToFelt(cid);
        print('  - CID felt: $cidFelt');
      } catch (e) {
        print('  - Error with CID: $e');
      }
      
      try {
        final memoryNameFelt = _stringToFelt(memoryName);
        print('  - Memory Name felt: $memoryNameFelt');
      } catch (e) {
        print('  - Error with Memory Name: $e');
      }

      // Construir la calldata
      final calldata = List<Felt>.from([
        // Hash Commit
        _stringToFelt(hashCommit),
        
        // Encrypted Secret
        _stringToFelt(encryptedSecret),
        
        // CID
        _stringToFelt(cid),
        
        // Timestamp
        Felt.fromInt(unlockTimestamp),
        
        // Tipo de desbloqueo (convertir 'timestamp' a número)
        Felt.fromInt(1), // 1 para timestamp, 2 para heirs
        
        // Memory Name
        _stringToFelt(memoryName),
      ]);

      print('📦 Calldata length: ${calldata.length}');
      print('📦 Calldata preview:');
      for (int i = 0; i < calldata.length && i < 10; i++) {
        print('  [$i]: ${calldata[i]}');
      }
      if (calldata.length > 10) {
        print('  ... and ${calldata.length - 10} more items');
      }

      // 6. Crear la lista de FunctionCall
      final calls = [
        FunctionCall(
          contractAddress: Felt.fromHexString(StarknetConfig.contractAddress),
          entryPointSelector: selector,
          calldata: calldata,
        ),
      ];

      // 7. Ejecutar la transacción
      final result = await account.execute(functionCalls: calls);

      print('✅ Metadata guardada exitosamente');
      print('📝 Resultado: $result');

      // // Mostrar mensaje de éxito
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(
      //     content: Text('Memory created successfully! Transaction hash:'),
      //     backgroundColor: Colors.green,
      //   ),
      // );

      // TODO: Navegar a la siguiente pantalla o cerrar esta
    } catch (e) {
      print('❌ Error al guardar metadata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving metadata: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primary,
          automaticallyImplyLeading: false,
          leading: FlutterFlowIconButton(
            borderColor: Colors.transparent,
            borderRadius: 30.0,
            borderWidth: 1.0,
            buttonSize: 60.0,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: FlutterFlowTheme.of(context).tertiary,
              size: 30.0,
            ),
            onPressed: () async {
              context.pop();
            },
          ),
          title: Text(
            'Text Creation',
            style: FlutterFlowTheme.of(context).headlineMedium.override(
                  font: GoogleFonts.interTight(
                    fontWeight:
                        FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                  ),
                  color: FlutterFlowTheme.of(context).tertiary,
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                  fontWeight:
                      FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                  fontStyle:
                      FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                ),
          ),
          actions: [],
          centerTitle: true,
          elevation: 2.0,
        ),
        body: SafeArea(
          top: true,
          child: Form(
            key: _model.formKey,
            autovalidateMode: AutovalidateMode.disabled,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Align(
                    alignment: AlignmentDirectional(0.0, 0.0),
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'Design your own memory',
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.roboto(
                                fontWeight: FontWeight.w600,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontStyle,
                              ),
                              fontSize: 28.0,
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w600,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(10.0),
                    child: Container(
                      width: 350.0,
                      child: TextFormField(
                        controller: _model.memoryNameTextController,
                        focusNode: _model.memoryNameFocusNode,
                        autofocus: false,
                        obscureText: false,
                        decoration: InputDecoration(
                          isDense: true,
                          labelStyle:
                              FlutterFlowTheme.of(context).labelMedium.override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                          hintText: 'Memory Name',
                          hintStyle:
                              FlutterFlowTheme.of(context).labelMedium.override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: FlutterFlowTheme.of(context).alternate,
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Color(0x00000000),
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: FlutterFlowTheme.of(context).error,
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: FlutterFlowTheme.of(context).error,
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          filled: true,
                          fillColor:
                              FlutterFlowTheme.of(context).secondaryBackground,
                        ),
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(
                                fontWeight: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontWeight,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontStyle,
                              ),
                              letterSpacing: 0.0,
                              fontWeight: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontWeight,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                        textAlign: TextAlign.center,
                        cursorColor: FlutterFlowTheme.of(context).primaryText,
                        validator: _model.memoryNameTextControllerValidator
                            .asValidator(context),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(10.0),
                    child: Container(
                      width: 350.0,
                      child: TextFormField(
                        controller: _model.memoryDescriptionTextController,
                        focusNode: _model.memoryDescriptionFocusNode,
                        autofocus: false,
                        obscureText: false,
                        decoration: InputDecoration(
                          isDense: true,
                          labelStyle:
                              FlutterFlowTheme.of(context).labelMedium.override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                          hintText: 'Memory Description',
                          hintStyle:
                              FlutterFlowTheme.of(context).labelMedium.override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .labelMedium
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: FlutterFlowTheme.of(context).alternate,
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Color(0x00000000),
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: FlutterFlowTheme.of(context).error,
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: FlutterFlowTheme.of(context).error,
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          filled: true,
                          fillColor:
                              FlutterFlowTheme.of(context).secondaryBackground,
                        ),
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(
                                fontWeight: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontWeight,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontStyle,
                              ),
                              letterSpacing: 0.0,
                              fontWeight: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontWeight,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                        textAlign: TextAlign.center,
                        cursorColor: FlutterFlowTheme.of(context).primaryText,
                        validator: _model
                            .memoryDescriptionTextControllerValidator
                            .asValidator(context),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(10.0),
                    child: Container(
                      width: 350.0,
                      child: DropdownButtonFormField<String>(
                        value: _unlockType,
                        decoration: InputDecoration(
                          labelText: 'Unlock Type',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'timestamp',
                            child: Text('Time-based Unlock'),
                          ),
                          DropdownMenuItem(
                            value: 'heris',
                            child: Text('Heirs-based Unlock'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _unlockType = value!;
                          });
                        },
                      ),
                    ),
                  ),
                  if (_unlockType == 'timestamp')
                    Padding(
                      padding: EdgeInsets.all(10.0),
                      child: FFButtonWidget(
                        onPressed: () async {
                          await showModalBottomSheet<bool>(
                            context: context,
                            builder: (context) {
                              final _datePickedCupertinoTheme =
                                  CupertinoTheme.of(context);
                              return Container(
                                height: MediaQuery.of(context).size.height / 3,
                                width: MediaQuery.of(context).size.width,
                                color: FlutterFlowTheme.of(context)
                                    .secondaryBackground,
                                child: CupertinoTheme(
                                  data: _datePickedCupertinoTheme.copyWith(
                                    textTheme: _datePickedCupertinoTheme
                                        .textTheme
                                        .copyWith(
                                      dateTimePickerTextStyle: FlutterFlowTheme
                                              .of(context)
                                          .headlineMedium
                                          .override(
                                            font: GoogleFonts.interTight(
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .headlineMedium
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .headlineMedium
                                                      .fontStyle,
                                            ),
                                            color: FlutterFlowTheme.of(context)
                                                .primaryText,
                                            letterSpacing: 0.0,
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .headlineMedium
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .headlineMedium
                                                    .fontStyle,
                                          ),
                                    ),
                                  ),
                                  child: CupertinoDatePicker(
                                    mode: CupertinoDatePickerMode.dateAndTime,
                                    minimumDate: getCurrentTimestamp,
                                    initialDateTime: getCurrentTimestamp,
                                    maximumDate: DateTime(2050),
                                    backgroundColor:
                                        FlutterFlowTheme.of(context)
                                            .secondaryBackground,
                                    use24hFormat: false,
                                    onDateTimeChanged: (newDateTime) =>
                                        safeSetState(() {
                                      _model.datePicked = newDateTime;
                                    }),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        text: valueOrDefault<String>(
                          _model.datePicked?.toString(),
                          'Select Unlock Date',
                        ),
                        options: FFButtonOptions(
                          width: 350.0,
                          height: 40.0,
                          padding: EdgeInsetsDirectional.fromSTEB(
                              16.0, 0.0, 16.0, 0.0),
                          iconPadding:
                              EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 0.0),
                          color: FlutterFlowTheme.of(context).secondaryBackground,
                          textStyle:
                              FlutterFlowTheme.of(context).bodyMedium.override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                  ),
                          elevation: 0.0,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(10.0),
                          child: Container(
                            width: 350.0,
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Number of Heirs',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                setState(() {
                                  _heirsCount = int.tryParse(value) ?? 0;
                                });
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(10.0),
                          child: Container(
                            width: 350.0,
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Minimum Consensus',
                                helperText: 'Number of heirs required to unlock the memory',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                setState(() {
                                  _minConsensus = int.tryParse(value) ?? 0;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  Container(
                    width: 350.0,
                    child: TextFormField(
                      controller: _model.secretTextTextController,
                      focusNode: _model.secretTextFocusNode,
                      autofocus: false,
                      obscureText: false,
                      decoration: InputDecoration(
                        isDense: true,
                        labelStyle:
                            FlutterFlowTheme.of(context).labelMedium.override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .fontStyle,
                                ),
                        hintText: 'Secret Text',
                        hintStyle:
                            FlutterFlowTheme.of(context).labelMedium.override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelMedium
                                        .fontStyle,
                                  ),
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .fontStyle,
                                ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: FlutterFlowTheme.of(context).alternate,
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Color(0x00000000),
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: FlutterFlowTheme.of(context).error,
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: FlutterFlowTheme.of(context).error,
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        filled: true,
                        fillColor:
                            FlutterFlowTheme.of(context).secondaryBackground,
                      ),
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontWeight,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                            letterSpacing: 0.0,
                            fontWeight: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontWeight,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontStyle,
                          ),
                      maxLines: 18,
                      cursorColor: FlutterFlowTheme.of(context).primaryText,
                      validator: _model.secretTextTextControllerValidator
                          .asValidator(context),
                    ),
                  ),
                  Padding(
                    padding:
                        EdgeInsetsDirectional.fromSTEB(0.0, 24.0, 0.0, 12.0),
                    child: FFButtonWidget(
                      onPressed: () async {
                        if (_model.formKey.currentState?.validate() ?? false) {
                          if (_model.memoryNameTextController.text.isEmpty ||
                              _model.secretTextTextController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Please fill all required fields'),
                              ),
                            );
                            return;
                          }

                          if (_unlockType == 'heris' && (_heirsCount <= 0 || _minConsensus <= 0)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Please set valid heirs count and minimum consensus'),
                              ),
                            );
                            return;
                          }

                          await _uploadToIPFS();
                        }
                      },
                      text: 'Submit Memory',
                      icon: Icon(
                        Icons.receipt_long,
                        size: 15.0,
                      ),
                      options: FFButtonOptions(
                        width: 350.0,
                        height: 54.0,
                        padding: EdgeInsets.all(0.0),
                        iconPadding:
                            EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 0.0),
                        color: FlutterFlowTheme.of(context).primary,
                        textStyle:
                            FlutterFlowTheme.of(context).titleSmall.override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontStyle,
                                  ),
                                  color: FlutterFlowTheme.of(context).tertiary,
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .fontStyle,
                                ),
                        elevation: 4.0,
                        borderSide: BorderSide(
                          color: Colors.transparent,
                          width: 1.0,
                        ),
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
// ignore: implementation_imports
import 'package:dartssh2/src/utils/bcrypt.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;
import 'package:pointycastle/export.dart';

enum SshKeyGenerationAlgorithm {
  ed25519(
    storageAlgorithm: 'ed25519',
    label: 'Ed25519（推荐）',
    keyType: 'ssh-ed25519',
  ),
  rsa2048(
    storageAlgorithm: 'rsa-2048',
    label: 'RSA 2048',
    keyType: 'ssh-rsa',
  ),
  rsa4096(
    storageAlgorithm: 'rsa-4096',
    label: 'RSA 4096',
    keyType: 'ssh-rsa',
  ),
  ecdsaP256(
    storageAlgorithm: 'ecdsa-nistp256',
    label: 'ECDSA nistp256',
    keyType: 'ecdsa-sha2-nistp256',
  );

  const SshKeyGenerationAlgorithm({
    required this.storageAlgorithm,
    required this.label,
    required this.keyType,
  });

  final String storageAlgorithm;
  final String label;
  final String keyType;
}

class SshKeyMaterial {
  const SshKeyMaterial({
    required this.algorithm,
    required this.fingerprint,
    required this.publicKey,
    required this.comment,
  });

  final String algorithm;
  final String fingerprint;
  final String publicKey;
  final String comment;
}

class GeneratedSshKeyMaterial extends SshKeyMaterial {
  const GeneratedSshKeyMaterial({
    required super.algorithm,
    required super.fingerprint,
    required super.publicKey,
    required super.comment,
    required this.privateKey,
  });

  final String privateKey;
}

typedef _PrivateKeyFieldWriter = void Function(_SshBinaryWriter writer);

class _GeneratedKeyData {
  _GeneratedKeyData({
    required this.keyType,
    required this.publicKeyBlob,
    required this.writePrivateFields,
  });

  final String keyType;
  final Uint8List publicKeyBlob;
  final _PrivateKeyFieldWriter writePrivateFields;
}

class SshKeyGenerationService {
  const SshKeyGenerationService();

  static const _opensshMagic = 'openssh-key-v1';
  static const _opensshPemType = 'OPENSSH PRIVATE KEY';
  static const _cipherNameAes256Ctr = 'aes256-ctr';
  static const _unencryptedBlockSize = 8;
  static const _encryptedBlockSize = 16;
  static const _bcryptSaltLength = 16;
  static const _bcryptRounds = 16;

  static final math.Random _random = math.Random.secure();

  SshKeyMaterial inspectPrivateKey(
    String privateKeyPem, {
    String? passphrase,
    String? comment,
  }) {
    final normalizedPassphrase =
        passphrase == null || passphrase.isEmpty ? null : passphrase;
    final normalizedComment = _normalizeComment(comment);
    final keyPair = SSHKeyPair.fromPem(privateKeyPem, normalizedPassphrase).first;
    final publicKeyBlob = keyPair.toPublicKey().encode();
    final keyType = keyPair.name;

    return SshKeyMaterial(
      algorithm: _describeAlgorithm(keyType, publicKeyBlob),
      fingerprint: _buildFingerprint(publicKeyBlob),
      publicKey: _buildPublicKeyLine(
        keyType: keyType,
        publicKeyBlob: publicKeyBlob,
        comment: normalizedComment,
      ),
      comment: normalizedComment,
    );
  }

  GeneratedSshKeyMaterial generate({
    required SshKeyGenerationAlgorithm algorithm,
    required String comment,
    String? passphrase,
  }) {
    final normalizedComment = _normalizeComment(comment);
    if (normalizedComment.isEmpty) {
      throw ArgumentError('密钥注释不能为空');
    }

    final normalizedPassphrase =
        passphrase == null || passphrase.isEmpty ? null : passphrase;
    final generated = switch (algorithm) {
      SshKeyGenerationAlgorithm.ed25519 => _generateEd25519(),
      SshKeyGenerationAlgorithm.rsa2048 => _generateRsa(2048),
      SshKeyGenerationAlgorithm.rsa4096 => _generateRsa(4096),
      SshKeyGenerationAlgorithm.ecdsaP256 => _generateEcdsaP256(),
    };

    return GeneratedSshKeyMaterial(
      algorithm: algorithm.storageAlgorithm,
      fingerprint: _buildFingerprint(generated.publicKeyBlob),
      publicKey: _buildPublicKeyLine(
        keyType: generated.keyType,
        publicKeyBlob: generated.publicKeyBlob,
        comment: normalizedComment,
      ),
      comment: normalizedComment,
      privateKey: _encodeOpenSshPem(
        keyType: generated.keyType,
        publicKeyBlob: generated.publicKeyBlob,
        writePrivateFields: generated.writePrivateFields,
        comment: normalizedComment,
        passphrase: normalizedPassphrase,
      ),
    );
  }

  _GeneratedKeyData _generateEd25519() {
    final signingKey = ed25519.SigningKey.generate();
    final publicKey = Uint8List.fromList(signingKey.verifyKey.asTypedList);
    final privateKey = Uint8List.fromList(signingKey.asTypedList);

    final publicWriter = _SshBinaryWriter()
      ..writeUtf8(SshKeyGenerationAlgorithm.ed25519.keyType)
      ..writeString(publicKey);

    return _GeneratedKeyData(
      keyType: SshKeyGenerationAlgorithm.ed25519.keyType,
      publicKeyBlob: publicWriter.takeBytes(),
      writePrivateFields: (writer) {
        writer.writeString(publicKey);
        writer.writeString(privateKey);
      },
    );
  }

  _GeneratedKeyData _generateRsa(int bits) {
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
          _newSecureRandom(),
        ),
      );

    final pair = generator.generateKeyPair();
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;
    final e = publicKey.publicExponent!;
    final n = publicKey.modulus!;
    final d = privateKey.privateExponent!;
    final p = privateKey.p!;
    final q = privateKey.q!;
    final iqmp = q.modInverse(p);

    final publicWriter = _SshBinaryWriter()
      ..writeUtf8(SshKeyGenerationAlgorithm.rsa2048.keyType)
      ..writeMpint(e)
      ..writeMpint(n);

    return _GeneratedKeyData(
      keyType: SshKeyGenerationAlgorithm.rsa2048.keyType,
      publicKeyBlob: publicWriter.takeBytes(),
      writePrivateFields: (writer) {
        writer
          ..writeMpint(n)
          ..writeMpint(e)
          ..writeMpint(d)
          ..writeMpint(iqmp)
          ..writeMpint(p)
          ..writeMpint(q);
      },
    );
  }

  _GeneratedKeyData _generateEcdsaP256() {
    final domainParameters = ECCurve_secp256r1();
    final generator = ECKeyGenerator()
      ..init(
        ParametersWithRandom(
          ECKeyGeneratorParameters(domainParameters),
          _newSecureRandom(),
        ),
      );

    final pair = generator.generateKeyPair();
    final publicKey = pair.publicKey as ECPublicKey;
    final privateKey = pair.privateKey as ECPrivateKey;
    final q = Uint8List.fromList(publicKey.Q!.getEncoded(false));
    const keyType = 'ecdsa-sha2-nistp256';
    const curveId = 'nistp256';

    final publicWriter = _SshBinaryWriter()
      ..writeUtf8(keyType)
      ..writeUtf8(curveId)
      ..writeString(q);

    return _GeneratedKeyData(
      keyType: keyType,
      publicKeyBlob: publicWriter.takeBytes(),
      writePrivateFields: (writer) {
        writer
          ..writeUtf8(curveId)
          ..writeString(q)
          ..writeMpint(privateKey.d!);
      },
    );
  }

  String _encodeOpenSshPem({
    required String keyType,
    required Uint8List publicKeyBlob,
    required _PrivateKeyFieldWriter writePrivateFields,
    required String comment,
    required String? passphrase,
  }) {
    final privateKeyBlob = _buildPrivateKeyBlob(
      keyType: keyType,
      writePrivateFields: writePrivateFields,
      comment: comment,
      blockSize:
          passphrase == null ? _unencryptedBlockSize : _encryptedBlockSize,
    );

    var cipherName = 'none';
    var kdfName = 'none';
    var kdfOptions = Uint8List(0);
    var protectedPrivateKeyBlob = privateKeyBlob;

    if (passphrase != null) {
      cipherName = _cipherNameAes256Ctr;
      kdfName = 'bcrypt';

      final salt = _randomBytes(_bcryptSaltLength);
      final derived = Uint8List(48);
      final passphraseBytes = Uint8List.fromList(utf8.encode(passphrase));
      final status = bcrypt_pbkdf(
        passphraseBytes,
        passphraseBytes.length,
        salt,
        salt.length,
        derived,
        derived.length,
        _bcryptRounds,
      );

      if (status != 0) {
        throw StateError('bcrypt_pbkdf 生成 OpenSSH 密钥失败');
      }

      kdfOptions = _encodeBcryptOptions(salt, _bcryptRounds);
      protectedPrivateKeyBlob = _aesCtrTransform(
        privateKeyBlob,
        Uint8List.sublistView(derived, 0, 32),
        Uint8List.sublistView(derived, 32, 48),
      );
    }

    final writer = _SshBinaryWriter()
      ..writeBytes(Uint8List.fromList(ascii.encode(_opensshMagic)))
      ..writeUint8(0)
      ..writeUtf8(cipherName)
      ..writeUtf8(kdfName)
      ..writeString(kdfOptions)
      ..writeUint32(1)
      ..writeString(publicKeyBlob)
      ..writeString(protectedPrivateKeyBlob);

    return _wrapPem(_opensshPemType, writer.takeBytes());
  }

  Uint8List _buildPrivateKeyBlob({
    required String keyType,
    required _PrivateKeyFieldWriter writePrivateFields,
    required String comment,
    required int blockSize,
  }) {
    final checkInt = _randomUint32();
    final writer = _SshBinaryWriter()
      ..writeUint32(checkInt)
      ..writeUint32(checkInt)
      ..writeUtf8(keyType);

    writePrivateFields(writer);
    writer.writeUtf8(comment);
    _padWriter(writer, blockSize);
    return writer.takeBytes();
  }

  Uint8List _encodeBcryptOptions(Uint8List salt, int rounds) {
    final writer = _SshBinaryWriter()
      ..writeString(salt)
      ..writeUint32(rounds);
    return writer.takeBytes();
  }

  Uint8List _aesCtrTransform(
    Uint8List input,
    Uint8List key,
    Uint8List iv,
  ) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));
    final output = Uint8List(input.length);
    cipher.processBytes(input, 0, input.length, output, 0);
    return output;
  }

  SecureRandom _newSecureRandom() {
    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(_randomBytes(32)));
    return secureRandom;
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  int _randomUint32() {
    final bytes = _randomBytes(4);
    return ByteData.sublistView(bytes).getUint32(0, Endian.big);
  }

  String _buildFingerprint(Uint8List publicKeyBlob) {
    final digest = sha256.convert(publicKeyBlob);
    return 'SHA256:${base64Encode(digest.bytes).replaceAll('=', '')}';
  }

  String _buildPublicKeyLine({
    required String keyType,
    required Uint8List publicKeyBlob,
    required String comment,
  }) {
    final commentSuffix = comment.isEmpty ? '' : ' $comment';
    return '$keyType ${base64Encode(publicKeyBlob)}$commentSuffix';
  }

  String _normalizeComment(String? comment) {
    return comment?.trim() ?? '';
  }

  String _describeAlgorithm(String keyType, Uint8List publicKeyBlob) {
    if (keyType == 'ssh-ed25519') {
      return 'ed25519';
    }
    if (keyType == 'ecdsa-sha2-nistp256') {
      return 'ecdsa-nistp256';
    }
    if (keyType.startsWith('ecdsa-sha2-')) {
      return keyType.replaceFirst('ecdsa-sha2-', 'ecdsa-');
    }
    if (keyType == 'ssh-rsa') {
      final reader = _SshBinaryReader(publicKeyBlob);
      reader.readUtf8();
      reader.readMpint();
      final modulus = reader.readMpint();
      return 'rsa-${modulus.bitLength}';
    }
    return keyType.replaceFirst('ssh-', '');
  }

  void _padWriter(_SshBinaryWriter writer, int blockSize) {
    for (var padding = 1; writer.length % blockSize != 0; padding++) {
      writer.writeUint8(padding);
    }
  }

  String _wrapPem(String type, Uint8List content) {
    final encoded = base64Encode(content);
    final buffer = StringBuffer()..writeln('-----BEGIN $type-----');
    for (var index = 0; index < encoded.length; index += 70) {
      final end = math.min(index + 70, encoded.length);
      buffer.writeln(encoded.substring(index, end));
    }
    buffer.write('-----END $type-----');
    return buffer.toString();
  }
}

class _SshBinaryWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  int get length => _builder.length;

  void writeUint8(int value) {
    _builder.addByte(value);
  }

  void writeUint32(int value) {
    final byteData = ByteData(4)..setUint32(0, value, Endian.big);
    _builder.add(byteData.buffer.asUint8List());
  }

  void writeBytes(Uint8List value) {
    _builder.add(value);
  }

  void writeString(Uint8List value) {
    writeUint32(value.length);
    writeBytes(value);
  }

  void writeUtf8(String value) {
    writeString(Uint8List.fromList(utf8.encode(value)));
  }

  void writeMpint(BigInt value) {
    writeString(_encodeMpint(value));
  }

  Uint8List takeBytes() {
    return _builder.takeBytes();
  }
}

class _SshBinaryReader {
  _SshBinaryReader(this._data) : _byteData = ByteData.sublistView(_data);

  final Uint8List _data;
  final ByteData _byteData;
  var _offset = 0;

  int readUint32() {
    final value = _byteData.getUint32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  Uint8List readString() {
    final length = readUint32();
    final value = Uint8List.sublistView(_data, _offset, _offset + length);
    _offset += length;
    return value;
  }

  String readUtf8() {
    return utf8.decode(readString());
  }

  BigInt readMpint() {
    return _decodeBigIntWithSign(1, readString());
  }
}

final BigInt _byteMask = BigInt.from(0xff);
final BigInt _negativeFlag = BigInt.from(0x80);

Uint8List _encodeMpint(BigInt number) {
  if (number == BigInt.zero) {
    return Uint8List.fromList([0]);
  }

  final rawSize = (number.bitLength + 7) >> 3;
  final needsPaddingByte =
      ((number >> ((rawSize - 1) * 8)) & _negativeFlag) == _negativeFlag
          ? 1
          : 0;

  final result = Uint8List(rawSize + needsPaddingByte);
  var current = number;
  for (var index = 0; index < rawSize; index++) {
    result[result.length - index - 1] = (current & _byteMask).toInt();
    current = current >> 8;
  }
  return result;
}

BigInt _decodeBigIntWithSign(int sign, List<int> magnitude) {
  if (sign == 0 || magnitude.isEmpty) {
    return BigInt.zero;
  }

  var result = BigInt.zero;
  for (var i = 0; i < magnitude.length; i++) {
    final value = magnitude[magnitude.length - i - 1];
    result |= (BigInt.from(value) << (8 * i));
  }

  if (result != BigInt.zero) {
    result = sign < 0
        ? result.toSigned(result.bitLength)
        : result.toUnsigned(result.bitLength);
  }
  return result;
}

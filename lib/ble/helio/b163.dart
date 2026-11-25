// ECDH on NIST B-163 (sect163r2), the curve the Amazfit Helio Strap uses for its
// auth handshake.
//
// A Dart port of the open-source `unstrap` project's `B163.kt` (MIT/Apache-2.0,
// github.com/sayed0am/unstrap), whose protocol notes are the source of the wire
// facts here. Field GF(2^163), f(x) = x^163 + x^7 + x^6 + x^3 + 1, curve
// y^2 + xy = x^3 + x^2 + b. Elements are polynomials held as BigInt bit sets.
// Speed is irrelevant: one key pair and one shared secret per connection.
//
// Wire format: scalars and coordinates are 24-byte LITTLE-endian. A public key
// is X || Y (48 bytes, no prefix); the shared secret is the X coordinate.

import 'dart:math';
import 'dart:typed_data';

const int _m = 163;
final BigInt _one = BigInt.one;
final BigInt _f = (_one << 163) | (_one << 7) | (_one << 6) | (_one << 3) | _one;
final BigInt _a = _one;

final BigInt kB163B = BigInt.parse('20a601907b8c953ca1481eb10512f78744a3205fd', radix: 16);
final BigInt kB163Gx = BigInt.parse('3f0eba16286a2d57ea0991168d4994637e8343e36', radix: 16);
final BigInt kB163Gy = BigInt.parse('0d51fbc6c71a0094fa2cdd545b11c5c0c797324f1', radix: 16);
final BigInt kB163N = BigInt.parse('40000000000000000000292fe77e70c12a4234c33', radix: 16);

const int kB163ScalarBytes = 24;
const int kB163PublicKeyBytes = 48;

bool _bit(BigInt v, int i) => ((v >> i) & _one) == _one;

/// An affine point; [B163Point.infinity] is the identity.
class B163Point {
  final BigInt x, y;
  final bool isInfinity;
  const B163Point._(this.x, this.y, this.isInfinity);
  B163Point(this.x, this.y) : isInfinity = false;
  static final B163Point infinity = B163Point._(BigInt.zero, BigInt.zero, true);
}

final B163Point kB163G = B163Point(kB163Gx, kB163Gy);

BigInt _reduce(BigInt v) {
  var r = v;
  while (r.bitLength > _m) {
    r = r ^ (_f << (r.bitLength - 1 - _m));
  }
  return r;
}

/// Field multiplication.
BigInt b163Mul(BigInt a, BigInt b) {
  var result = BigInt.zero;
  var x = a;
  for (var i = 0; i < b.bitLength; i++) {
    if (_bit(b, i)) result = result ^ x;
    x = x << 1;
    if (_bit(x, _m)) x = x ^ _f;
  }
  return _reduce(result);
}

BigInt _sqr(BigInt a) => b163Mul(a, a);

/// Field inverse by the extended Euclidean algorithm for binary polynomials.
BigInt b163Inv(BigInt a) {
  if (a == BigInt.zero) throw ArgumentError('Zero has no inverse');
  var u = a, v = _f;
  var g1 = _one, g2 = BigInt.zero;
  while (u != _one) {
    var j = u.bitLength - v.bitLength;
    if (j < 0) {
      final tu = u;
      u = v;
      v = tu;
      final tg = g1;
      g1 = g2;
      g2 = tg;
      j = -j;
    }
    u = u ^ (v << j);
    g1 = g1 ^ (g2 << j);
  }
  return _reduce(g1);
}

bool b163IsOnCurve(B163Point p) {
  if (p.isInfinity) return true;
  if (p.x.bitLength > _m || p.y.bitLength > _m) return false;
  final lhs = _sqr(p.y) ^ b163Mul(p.x, p.y);
  final x2 = _sqr(p.x);
  final rhs = b163Mul(x2, p.x) ^ b163Mul(_a, x2) ^ kB163B;
  return lhs == rhs;
}

B163Point b163Double(B163Point p) {
  if (p.isInfinity || p.x == BigInt.zero) return B163Point.infinity;
  final lambda = p.x ^ b163Mul(p.y, b163Inv(p.x));
  final x3 = _sqr(lambda) ^ lambda ^ _a;
  final y3 = _sqr(p.x) ^ b163Mul(lambda ^ _one, x3);
  return B163Point(x3, y3);
}

B163Point b163Add(B163Point p, B163Point q) {
  if (p.isInfinity) return q;
  if (q.isInfinity) return p;
  if (p.x == q.x) return p.y == q.y ? b163Double(p) : B163Point.infinity;
  final lambda = b163Mul(p.y ^ q.y, b163Inv(p.x ^ q.x));
  final x3 = _sqr(lambda) ^ lambda ^ p.x ^ q.x ^ _a;
  final y3 = b163Mul(lambda, p.x ^ x3) ^ x3 ^ p.y;
  return B163Point(x3, y3);
}

B163Point b163Multiply(BigInt k, B163Point p) {
  var result = B163Point.infinity;
  for (var i = k.bitLength - 1; i >= 0; i--) {
    result = b163Double(result);
    if (_bit(k, i)) result = b163Add(result, p);
  }
  return result;
}

/// [v] as [size] little-endian bytes.
Uint8List b163ToLe(BigInt v, [int size = kB163ScalarBytes]) {
  if (v.bitLength > size * 8) throw ArgumentError('Value too large for $size bytes');
  final out = Uint8List(size);
  var t = v;
  final mask = BigInt.from(0xFF);
  for (var i = 0; i < size; i++) {
    out[i] = (t & mask).toInt();
    t = t >> 8;
  }
  return out;
}

BigInt b163FromLe(List<int> bytes) {
  var v = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    v = (v << 8) | BigInt.from(bytes[i] & 0xFF);
  }
  return v;
}

Uint8List b163EncodePoint(B163Point p) =>
    Uint8List.fromList([...b163ToLe(p.x), ...b163ToLe(p.y)]);

/// A 48-byte public key as a point, refused when it is not on the curve.
B163Point b163DecodePoint(List<int> bytes) {
  if (bytes.length != kB163PublicKeyBytes) {
    throw ArgumentError('Public key must be $kB163PublicKeyBytes bytes');
  }
  final p = B163Point(b163FromLe(bytes.sublist(0, 24)), b163FromLe(bytes.sublist(24, 48)));
  if (!b163IsOnCurve(p)) throw ArgumentError('Device public key is not on B-163');
  return p;
}

class B163KeyPair {
  final BigInt privateKey;
  final Uint8List publicKey;
  B163KeyPair._(this.privateKey, this.publicKey);

  factory B163KeyPair(BigInt privateKey) =>
      B163KeyPair._(privateKey, b163EncodePoint(b163Multiply(privateKey, kB163G)));

  /// A fresh key pair; [random] is injectable so a test is repeatable.
  factory B163KeyPair.generate([Random? random]) {
    final r = random ?? Random.secure();
    while (true) {
      var k = BigInt.zero;
      for (var i = 0; i < 21; i++) {
        k = (k << 8) | BigInt.from(r.nextInt(256));
      }
      k = k & ((_one << kB163N.bitLength) - _one);
      if (k > BigInt.zero && k < kB163N) return B163KeyPair(k);
    }
  }
}

/// The X coordinate of priv * peer, 24 bytes little-endian.
Uint8List b163SharedSecret(BigInt privateKey, List<int> peerPublic) {
  final s = b163Multiply(privateKey, b163DecodePoint(peerPublic));
  if (s.isInfinity) throw StateError('Shared secret is the point at infinity');
  return b163ToLe(s.x);
}

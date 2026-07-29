import 'package:flutter_test/flutter_test.dart';

import 'package:trackflow/data/local/database.dart';
import 'package:trackflow/data/repositories/tracking_repository_impl.dart';
import 'package:trackflow/domain/entities/carrier.dart';

void main() {
  group('TrackingRepositoryImpl', () {
    late TrackingRepositoryImpl repo;

    setUp(() {
      // isValidTrackingNumber と detectCarrier はDBを使わないため
      // インメモリDBで初期化しても安全
      repo = TrackingRepositoryImpl(AppDatabase.inMemory());
    });

    group('isValidTrackingNumber', () {
      // 有効な追跡番号
      test('11桁の数字は有効', () {
        expect(repo.isValidTrackingNumber('12345678901'), isTrue);
      });

      test('ハイフン入りの11桁は有効', () {
        expect(repo.isValidTrackingNumber('123-4567-8901'), isTrue);
      });

      test('12桁の数字は有効', () {
        expect(repo.isValidTrackingNumber('123456789012'), isTrue);
      });

      test('14桁の数字は有効', () {
        expect(repo.isValidTrackingNumber('12345678901234'), isTrue);
      });

      // 無効な追跡番号
      test('空文字は無効', () {
        expect(repo.isValidTrackingNumber(''), isFalse);
      });

      test('9桁の数字は無効', () {
        expect(repo.isValidTrackingNumber('123456789'), isFalse);
      });

      test('15桁の数字は無効', () {
        expect(repo.isValidTrackingNumber('123456789012345'), isFalse);
      });

      test('非数字を含む文字列は無効', () {
        expect(repo.isValidTrackingNumber('ABC123456789'), isFalse);
      });
    });

    group('detectCarrier', () {
      test('11桁は日本郵便と判定', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('12345678901'),
          equals(Carrier.japanPost),
        );
      });

      test('13桁は日本郵便と判定', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('1234567890123'),
          equals(Carrier.japanPost),
        );
      });

      test('12桁はヤマト運輸と判定', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('123456789012'),
          equals(Carrier.yamato),
        );
      });

      test('ハイフン入りの12桁もヤマト運輸と判定', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('1234-5678-9012'),
          equals(Carrier.yamato),
        );
      });

      test('9桁はnull', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('123456789'),
          isNull,
        );
      });

      test('14桁はnull（10桁と14桁は判定対象外）', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('12345678901234'),
          isNull,
        );
      });
    });
  });

  group('Carrier', () {
    test('fromStringで日本郵便を解決', () {
      expect(Carrier.fromString('japanPost'), equals(Carrier.japanPost));
    });

    test('fromStringでヤマト運輸を解決', () {
      expect(Carrier.fromString('yamato'), equals(Carrier.yamato));
    });

    test('fromStringで佐川急便を解決', () {
      expect(Carrier.fromString('sagawa'), equals(Carrier.sagawa));
    });

    test('不明な文字列はyamatoにフォールバック', () {
      expect(Carrier.fromString('unknown'), equals(Carrier.yamato));
    });

    test('displayNameが正しい', () {
      expect(Carrier.japanPost.displayName, '日本郵便');
      expect(Carrier.yamato.displayName, 'ヤマト運輸');
      expect(Carrier.sagawa.displayName, '佐川急便');
    });
  });
}

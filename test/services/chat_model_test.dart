import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/chat.dart';

void main() {
  group('ChatRoomSummary.fromJson — v_chat_rooms 행 파싱', () {
    test('정상 행 파싱 + unread 는 num→int 수렴', () {
      final r = ChatRoomSummary.fromJson({
        'id': 'r1',
        'other_nickname': '냥집사',
        'other_user_id': 'u2',
        'last_message_preview': '안녕하세요',
        'last_message_at': '2026-07-01T03:00:00Z',
        'unread_count': 2.0,
        'other_left': true,
        'context': 'business',
      });
      expect(r.otherNickname, '냥집사');
      expect(r.unreadCount, 2);
      expect(r.otherLeft, isTrue);
      expect(r.lastMessageAt, DateTime.parse('2026-07-01T03:00:00Z').toLocal());
      expect(r.isBusinessInquiry, isTrue);
      expect(r.isSupport, isFalse);
    });

    test('누락 필드 폴백 — 닉네임/미리보기/컨텍스트/날짜', () {
      final r = ChatRoomSummary.fromJson({'id': 'r1'});
      expect(r.otherNickname, '알 수 없음');
      expect(r.lastMessage, '');
      expect(r.lastMessageAt, isNull);
      expect(r.unreadCount, 0);
      expect(r.otherLeft, isFalse);
      expect(r.context, 'personal');
      expect(r.isBusinessInquiry, isFalse);
    });

    test('상대가 고객센터면 isSupport(목록 최상단 고정 근거)', () {
      final r = ChatRoomSummary.fromJson({
        'id': 'r1',
        'other_nickname': '고객센터',
      });
      expect(r.isSupport, isTrue);
    });
  });

  group('ChatMessage.fromJson — 내 메시지 판정', () {
    final row = {
      'id': 'm1',
      'room_id': 'r1',
      'sender_id': 'u1',
      'content': 'hello',
      'created_at': '2026-07-01T03:00:00Z',
    };

    test('sender 가 나면 mine', () {
      expect(ChatMessage.fromJson(row, 'u1').mine, isTrue);
    });

    test('sender 가 타인이면 mine=false', () {
      expect(ChatMessage.fromJson(row, 'u2').mine, isFalse);
    });

    test('image_url 이 비어있지 않을 때만 isImage', () {
      expect(ChatMessage.fromJson(row, 'u1').isImage, isFalse);
      expect(
        ChatMessage.fromJson({...row, 'image_url': ''}, 'u1').isImage,
        isFalse,
      );
      expect(
        ChatMessage.fromJson({
          ...row,
          'image_url': 'https://x/y.jpg',
        }, 'u1').isImage,
        isTrue,
      );
    });

    test('누락 필드 폴백 + 날짜 없으면 epoch 0', () {
      final m = ChatMessage.fromJson({'id': 'm1'}, 'u1');
      expect(m.roomId, '');
      expect(m.content, '');
      expect(m.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(m.mine, isFalse);
    });
  });
}

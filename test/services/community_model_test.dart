import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/community.dart';

void main() {
  group('Post.fromJson — v_post_feed 행 파싱', () {
    test('정상 행을 전 필드 파싱하고 날짜는 로컬 시간으로 변환한다', () {
      final p = Post.fromJson({
        'id': 'p1',
        'category': 'walk_together',
        'title': '산책 구해요',
        'content': '내용',
        'user_id': 'u1',
        'author_nickname': '멍멍이집사',
        'author_user_type': 'pet_owner',
        'created_at': '2026-07-01T03:00:00Z',
        'scheduled_at': '2026-07-02T09:00:00Z',
        'location': '청운동',
        'heart_count': 3,
        'comment_count': 1,
        'view_count': 10,
        'progress_status': 'matched',
        'hearted': true,
        'authored_as': 'business',
      });
      expect(p.id, 'p1');
      expect(p.category, 'walk_together');
      expect(p.authorNickname, '멍멍이집사');
      expect(p.createdAt, DateTime.parse('2026-07-01T03:00:00Z').toLocal());
      expect(p.scheduledAt, DateTime.parse('2026-07-02T09:00:00Z').toLocal());
      expect(p.heartCount, 3);
      expect(p.hearted, isTrue);
      expect(p.authoredAs, 'business');
    });

    test('누락 필드는 안전한 기본값으로 폴백한다', () {
      final p = Post.fromJson({'id': 'p1'});
      expect(p.category, 'free');
      expect(p.title, '');
      expect(p.authorNickname, '알 수 없음');
      expect(p.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(p.scheduledAt, isNull);
      expect(p.heartCount, 0);
      expect(p.hearted, isFalse);
      expect(p.progressStatus, 'recruiting');
      expect(p.authoredAs, 'personal');
      expect(p.isEdited, isFalse);
    });

    test('카운트가 double 로 와도 int 로 수렴한다(PostgREST numeric)', () {
      final p = Post.fromJson({
        'id': 'p1',
        'heart_count': 3.0,
        'view_count': 7.9,
      });
      expect(p.heartCount, 3);
      expect(p.viewCount, 7);
    });

    test('hearted 는 boolean true 만 참으로 본다(문자열 "true" 거부)', () {
      expect(Post.fromJson({'id': 'p1', 'hearted': 'true'}).hearted, isFalse);
    });

    test('edited_at 이 있으면 isEdited', () {
      final p = Post.fromJson({
        'id': 'p1',
        'edited_at': '2026-07-01T00:00:00Z',
      });
      expect(p.isEdited, isTrue);
    });
  });

  group('Post.authorMoved — 작성자 지역 이동 판정', () {
    Post post({String? authorAddress, String? location}) => Post.fromJson({
      'id': 'p1',
      'author_address': authorAddress,
      'location': location,
    });

    test('작성자 현재 동 == 글의 동이면 이동 아님', () {
      expect(
        post(authorAddress: '서울 종로구 청운동', location: '청운동').authorMoved,
        isFalse,
      );
    });

    test('동이 다르면 이동으로 판정', () {
      expect(
        post(authorAddress: '서울 종로구 효자동', location: '청운동').authorMoved,
        isTrue,
      );
    });

    test('주소는 연속 공백이 섞여도 마지막 토큰으로 비교한다', () {
      expect(
        post(authorAddress: '서울  종로구   청운동', location: '청운동').authorMoved,
        isFalse,
      );
    });

    test('둘 중 하나라도 없거나 비면 이동 아님(경고 안 띄움)', () {
      expect(post(authorAddress: null, location: '청운동').authorMoved, isFalse);
      expect(
        post(authorAddress: '서울 종로구 청운동', location: null).authorMoved,
        isFalse,
      );
      expect(post(authorAddress: '  ', location: '청운동').authorMoved, isFalse);
    });
  });

  group('Post.copyWith — 낙관적 업데이트', () {
    test('지정 필드만 바뀌고 나머지는 유지된다', () {
      final p = Post.fromJson({'id': 'p1', 'title': '제목', 'heart_count': 1});
      final q = p.copyWith(hearted: true, heartCount: 2);
      expect(q.hearted, isTrue);
      expect(q.heartCount, 2);
      expect(q.title, '제목');
      expect(q.id, 'p1');
    });
  });

  group('Comment.fromJson', () {
    test('정상 행 파싱', () {
      final c = Comment.fromJson({
        'id': 'c1',
        'post_id': 'p1',
        'user_id': 'u1',
        'content': '댓글',
        'created_at': '2026-07-01T00:00:00Z',
        'author_nickname': '냥집사',
        'authored_as': 'business',
      });
      expect(c.postId, 'p1');
      expect(c.authorNickname, '냥집사');
      expect(c.authoredAs, 'business');
    });

    test('누락 필드 폴백', () {
      final c = Comment.fromJson({'id': 'c1'});
      expect(c.content, '');
      expect(c.authorNickname, '알 수 없음');
      expect(c.authoredAs, 'personal');
      expect(c.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });

  group('MyPet', () {
    // 사진 인증 면제는 신뢰도(trust_score)가 아니라 게시글 순번으로 정해진다
    // — 첫 글과 4·10번째 글에만 촬영 인증(자세한 규칙은 photo_gate_test.dart).
    test('촬영 인증은 첫 글에 필요하고 두 번째 글부터 면제', () {
      const first = MyPet(id: 'x', name: '뽀삐', species: '믹스', role: 'owner');
      expect(first.needsPhotoGate, isTrue);
      const second = MyPet(
        id: 'x',
        name: '뽀삐',
        species: '믹스',
        role: 'owner',
        verifyPostCount: 1,
      );
      expect(second.needsPhotoGate, isFalse);
    });
  });
}

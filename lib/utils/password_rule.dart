/// 비밀번호 복잡도 규칙 — **정본은 서버**(엣지 `signup` / `reset-password` /
/// `change-password` 가 각각 재검증한다). 여기 있는 건 서버 왕복 전에 알려주기
/// 위한 클라이언트 사본이다.
///
/// 한 곳에 모아 둔 이유: 가입·재설정·변경 세 화면이 각자 검사를 갖고 있다가
/// 규칙이 서로 갈렸다. 실제로 이런 상태였다.
///
///   · 가입   — 길이 8자만 검사(영문·숫자 확인 없음. 화면 힌트는 '영문 + 숫자
///              포함 8자 이상'이라 안내와 검사가 어긋났다)
///   · 재설정 — 8자 + 영문 + 숫자 (서버와 일치)
///   · 변경   — **6자만**. 구 `app._set_password` 정책이 남아, 가입에서 막은
///              단순 비밀번호를 '변경'으로 우회할 수 있었다
///
/// 규칙을 바꿀 때는 **서버 세 함수와 이 파일을 함께** 고칠 것. 클라이언트만
/// 조이면 서버가 통과시키고, 서버만 조이면 사용자가 이유 없는 실패를 본다.
library;

/// 영문과 숫자를 포함한 8자 이상인가.
///
/// 기호는 요구하지 않는다(서버 규칙과 동일) — 요구하도록 바꾸려면 엣지 함수
/// `signup` · `reset-password` · `change-password` 의 검사도 같이 고쳐야 한다.
bool isStrongPassword(String password) =>
    password.length >= 8 &&
    RegExp(r'[A-Za-z]').hasMatch(password) &&
    RegExp(r'\d').hasMatch(password);

/// 규칙을 어겼을 때 보여줄 안내 — 입력칸 힌트([kPasswordRuleHint])와 같은 말이어야
/// 사용자가 무엇을 고쳐야 할지 헷갈리지 않는다.
const kPasswordRuleMessage = '비밀번호는 영문과 숫자를 포함해 8자 이상이어야 해요';

/// 입력칸 힌트 문구.
const kPasswordRuleHint = '영문 + 숫자 포함 8자 이상';

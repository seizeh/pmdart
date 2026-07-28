// Flutter 가 첫 프레임을 그리면 스플래시를 걷어낸다.
//
// index.html 안의 인라인 <script> 였는데 파일로 뺐다 — CSP 의 script-src 를
// 'self' 만으로 유지하기 위해서다. 인라인으로 두면 'unsafe-inline'(스크립트
// 보호를 통째로 포기) 아니면 sha256 해시(이 파일을 한 글자만 고쳐도 조용히
// 차단되고, 그러면 스플래시가 영영 안 걷혀 흰 화면과 구분이 안 된다) 둘 중
// 하나를 골라야 한다. 파일로 빼면 그 선택 자체가 사라진다.
window.addEventListener('flutter-first-frame', function () {
  var s = document.getElementById('splash');
  if (!s) return;
  s.style.opacity = '0';
  setTimeout(function () { s.remove(); }, 300);
});

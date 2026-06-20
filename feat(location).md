내정보 → "지역 인증"에서 현재 위치(GPS)로 활동 지역(행정동)을 인증한다.                                                                                              
  좌표는 geolocator 로 직접 획득(accuracy·isMocked 필요), pmdb 의 verify-location                                                                                      
  Edge Function 이 Naver 역지오코딩 후 서버에서 인증 컬럼을 갱신한다.                                                                                                  
                                                                                                                                                                       
  - location_service / location_repository / location_verify_screen 신규                                                                                               
  - my_info_tab "지역 인증" 항목 → 실제 화면 연결 + 인증 상태 표시                                                                                                     
  - profile 모델/리포지토리: address·is_location_verified 노출                                                                                                         
  - pubspec: geolocator ^13.0.0

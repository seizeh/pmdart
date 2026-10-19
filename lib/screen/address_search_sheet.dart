import 'package:flutter/material.dart';

import '../services/juso_service.dart';
import '../theme/app_palette.dart';

/// 업체 등록의 사업장 주소 검색 바텀시트 — 행안부 도로명주소(juso) 검색 결과에서
/// 고르면 [JusoAddress] 를 돌려준다. 업체 등록 화면에서 분리했다(파일 크기 래칫, #155).

class AddressSearchSheet extends StatefulWidget {
  const AddressSearchSheet({super.key});

  @override
  State<AddressSearchSheet> createState() => AddressSearchSheetState();
}

class AddressSearchSheetState extends State<AddressSearchSheet> {
  final _ctrl = TextEditingController();
  List<JusoAddress> _results = const [];
  bool _searching = false;
  bool _searched = false;

  /// 실패·검색어 문제 안내(있으면 "검색 결과가 없어요" 대신 보인다).
  String? _message;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) return;
    setState(() => _searching = true);
    final r = await JusoService.instance.search(q);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searched = true;
      _results = r.addresses;
      _message = r.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '사업장 주소 검색',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(hintText: '도로명, 건물명 또는 지번'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                // 테마 기본 minimumSize(Size.fromHeight)는 최소 폭이 무한이라
                // Row(무한 폭 제약) 안에서는 레이아웃이 터진다 — 폭을 명시.
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(64, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: _searching ? null : _search,
                child: const Text('검색'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: _searching
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        _message ?? (_searched ? '검색 결과가 없어요' : '주소를 검색해주세요'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: context.colors.border),
                    itemBuilder: (context, i) {
                      final a = _results[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          a.roadAddr,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          a.jibunAddr,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textTertiary,
                          ),
                        ),
                        onTap: () => Navigator.pop(context, a),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

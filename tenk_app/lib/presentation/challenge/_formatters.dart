/// 챌린지 화면들이 공유하는 작은 포맷 헬퍼. intl 의존성 회피용.
library;

String formatWon(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}${buf.toString()}원';
}

String formatDate(DateTime dt) {
  final d = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

String formatPeriod(DateTime start, DateTime end) =>
    '${formatDate(start)} ~ ${formatDate(end)}';

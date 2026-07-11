String formatMoneyPaise(int paise) {
  final rupees = paise / 100;
  final whole = rupees.truncate();
  final fraction = (rupees - whole).abs();
  if (fraction < 0.005) {
    return 'Rs ${whole.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }
  return 'Rs ${rupees.toStringAsFixed(2)}';
}

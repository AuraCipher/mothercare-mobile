class StudentFeePayment {
  const StudentFeePayment({
    required this.id,
    required this.amount,
    required this.createdAt,
    this.receiptNumber,
    this.paymentMethod,
  });

  final String id;
  final int amount;
  final DateTime createdAt;
  final String? receiptNumber;
  final String? paymentMethod;

  factory StudentFeePayment.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'] as String?;
    return StudentFeePayment(
      id: json['id'] as String? ?? '',
      amount: json['amount'] is int ? json['amount'] as int : int.tryParse('${json['amount']}') ?? 0,
      createdAt: created != null ? DateTime.tryParse(created) ?? DateTime.now() : DateTime.now(),
      receiptNumber: json['receiptNumber'] as String?,
      paymentMethod: json['paymentMethod'] as String?,
    );
  }
}

class StudentFeeExtraItem {
  const StudentFeeExtraItem({required this.id, required this.name, required this.amount});

  final String id;
  final String name;
  final int amount;

  factory StudentFeeExtraItem.fromJson(Map<String, dynamic> json) {
    return StudentFeeExtraItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      amount: json['amount'] is int ? json['amount'] as int : int.tryParse('${json['amount']}') ?? 0,
    );
  }
}

class StudentFeeMonth {
  const StudentFeeMonth({
    required this.id,
    required this.year,
    required this.month,
    required this.status,
    required this.netAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.dueAmount,
    this.extraItems = const [],
    this.payments = const [],
  });

  final String id;
  final int year;
  final int month;
  final String status;
  final int netAmount;
  final int totalAmount;
  final int paidAmount;
  final int dueAmount;
  final List<StudentFeeExtraItem> extraItems;
  final List<StudentFeePayment> payments;

  factory StudentFeeMonth.fromJson(Map<String, dynamic> json) {
    final extras = json['extraItems'] as List<dynamic>? ?? [];
    final payments = json['payments'] as List<dynamic>? ?? [];
    return StudentFeeMonth(
      id: json['id'] as String? ?? '',
      year: json['year'] is int ? json['year'] as int : int.tryParse('${json['year']}') ?? 0,
      month: json['month'] is int ? json['month'] as int : int.tryParse('${json['month']}') ?? 0,
      status: json['status'] as String? ?? 'UNPAID',
      netAmount: json['netAmount'] is int ? json['netAmount'] as int : int.tryParse('${json['netAmount']}') ?? 0,
      totalAmount: json['totalAmount'] is int ? json['totalAmount'] as int : int.tryParse('${json['totalAmount']}') ?? 0,
      paidAmount: json['paidAmount'] is int ? json['paidAmount'] as int : int.tryParse('${json['paidAmount']}') ?? 0,
      dueAmount: json['dueAmount'] is int ? json['dueAmount'] as int : int.tryParse('${json['dueAmount']}') ?? 0,
      extraItems: extras.map((e) => StudentFeeExtraItem.fromJson(e as Map<String, dynamic>)).toList(),
      payments: payments.map((e) => StudentFeePayment.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class StudentFeesSummary {
  const StudentFeesSummary({
    required this.totalDuePaise,
    required this.totalPaidPaise,
    required this.balanceDuePaise,
    required this.unpaidCount,
  });

  final int totalDuePaise;
  final int totalPaidPaise;
  final int balanceDuePaise;
  final int unpaidCount;

  factory StudentFeesSummary.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    return StudentFeesSummary(
      totalDuePaise: parseInt(json['totalDuePaise']),
      totalPaidPaise: parseInt(json['totalPaidPaise']),
      balanceDuePaise: parseInt(json['balanceDuePaise']),
      unpaidCount: parseInt(json['unpaidCount']),
    );
  }
}

class StudentFeesData {
  const StudentFeesData({required this.summary, this.months = const []});

  final StudentFeesSummary summary;
  final List<StudentFeeMonth> months;

  factory StudentFeesData.fromJson(Map<String, dynamic> json) {
    final monthsRaw = json['months'] as List<dynamic>? ?? [];
    return StudentFeesData(
      summary: StudentFeesSummary.fromJson(json['summary'] as Map<String, dynamic>? ?? {}),
      months: monthsRaw.map((e) => StudentFeeMonth.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'summary': {
          'totalDuePaise': summary.totalDuePaise,
          'totalPaidPaise': summary.totalPaidPaise,
          'balanceDuePaise': summary.balanceDuePaise,
          'unpaidCount': summary.unpaidCount,
        },
        'months': months
            .map(
              (m) => {
                'id': m.id,
                'year': m.year,
                'month': m.month,
                'status': m.status,
                'netAmount': m.netAmount,
                'totalAmount': m.totalAmount,
                'paidAmount': m.paidAmount,
                'dueAmount': m.dueAmount,
                'extraItems': m.extraItems.map((e) => {'id': e.id, 'name': e.name, 'amount': e.amount}).toList(),
                'payments': m.payments
                    .map(
                      (p) => {
                        'id': p.id,
                        'amount': p.amount,
                        'createdAt': p.createdAt.toUtc().toIso8601String(),
                        'receiptNumber': p.receiptNumber,
                        'paymentMethod': p.paymentMethod,
                      },
                    )
                    .toList(),
              },
            )
            .toList(),
      };
}

const studentFeeMonthNames = [
  '',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

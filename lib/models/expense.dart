import 'package:isar/isar.dart';

part 'expense.g.dart';

@collection
class Expense {
  Id id = Isar.autoIncrement;

  late String category;

  late double amount;

  late DateTime date;

  // NEW FIELDS
  late String account;
  late String paymentMethod;
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/expense.dart';

late Isar isar;
late SharedPreferences prefs;

List<String> appCategories = [
  "Food & Dining",
  "Petrol & Vehicle",
  "Shopping",
  "Entertainment",
  "Sports & Health",
  "Bills & Rent"
];

Future<void> loadCategories() async {
  prefs = await SharedPreferences.getInstance();
  List<String>? saved = prefs.getStringList('appCategories');
  if (saved != null && saved.isNotEmpty) {
    appCategories = saved;
  }
}

void saveCategories() {
  prefs.setStringList('appCategories', appCategories);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await loadCategories();

  final dir = await getApplicationDocumentsDirectory();
  isar = await Isar.open(
    [ExpenseSchema],
    directory: dir.path,
  );

  runApp(const SyncSpendApp());
}

class SyncSpendApp extends StatefulWidget {
  const SyncSpendApp({super.key});

  @override
  State<SyncSpendApp> createState() => _SyncSpendAppState();
}

class _SyncSpendAppState extends State<SyncSpendApp> {
  final QuickActions quickActions = const QuickActions();
  String _currentRoute = 'dashboard';

  @override
  void initState() {
    super.initState();
    quickActions.initialize((String type) {
      if (type == 'action_quick_add') setState(() => _currentRoute = 'popup');
    });

    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(type: 'action_quick_add', localizedTitle: 'Add Expense', icon: 'ic_launcher'),
    ]);

    _checkNativeIntent();
  }

  Future<void> _checkNativeIntent() async {
    const platform = MethodChannel('com.studioa4.syncspend/intent');
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      final String? action = await platform.invokeMethod('getIntentAction');
      if (action == 'action_quick_add') {
        setState(() => _currentRoute = 'popup');
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to get intent: ${e.message}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF007AFF),
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF007AFF),
        scaffoldBackgroundColor: Colors.black,
      ),
      themeMode: ThemeMode.system,
      home: _currentRoute == 'popup' ? const MainBackground() : const DashboardScreen(),
    );
  }
}

// ==========================================
// APPLE-GRADE STATEFUL DASHBOARD (FINAL)
// ==========================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _timeFilter = "Month";
  int _touchedIndex = -1;
  int _offsetIndex = 0;

  Stream<List<Expense>> _watchExpenses() {
    return isar.expenses.where().sortByDateDesc().watch(fireImmediately: true);
  }

  IconData _getCategoryIcon(String category) {
    String cat = category.toLowerCase();
    if (cat.contains("food") || cat.contains("eat")) return CupertinoIcons.cart_fill;
    if (cat.contains("petrol") || cat.contains("fuel") || cat.contains("car") || cat.contains("bike")) return CupertinoIcons.car_fill;
    if (cat.contains("shop") || cat.contains("buy")) return CupertinoIcons.bag_fill;
    if (cat.contains("movie") || cat.contains("ent")) return CupertinoIcons.play_circle_fill;
    if (cat.contains("bill") || cat.contains("rent")) return CupertinoIcons.doc_text_fill;
    if (cat.contains("sport") || cat.contains("gym")) return CupertinoIcons.sportscourt_fill;
    if (cat.contains("health") || cat.contains("medic")) return CupertinoIcons.heart_fill;
    return CupertinoIcons.square_grid_2x2_fill;
  }

  void _openQuickAdd(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (context, anim1, anim2) => const QuickLogPopup(),
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutBack)),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color subTextColor = isDark ? Colors.white54 : Colors.black54;
    Color iconBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openQuickAdd(context),
        backgroundColor: isDark ? Colors.white : Colors.black,
        shape: const CircleBorder(),
        child: Icon(Icons.add, color: isDark ? Colors.black : Colors.white, size: 28),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Expense>>(
          stream: _watchExpenses(),
          builder: (context, snapshot) {
            final allExpenses = snapshot.data ?? [];

            // We lock the 'now' state to midnight to avoid time-zone calculation bugs
            final DateTime rawNow = DateTime.now();
            final DateTime now = DateTime(rawNow.year, rawNow.month, rawNow.day);

            // --- 1. DATA BOUNDING ENGINE ---
            DateTime oldestExpenseDate = now;
            if (allExpenses.isNotEmpty) {
              oldestExpenseDate = allExpenses.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
              oldestExpenseDate = DateTime(oldestExpenseDate.year, oldestExpenseDate.month, oldestExpenseDate.day);
            }

            int minOffset = 0;
            if (_timeFilter == "Week") {
              // Standardize to Monday
              DateTime currentMonday = now.subtract(Duration(days: now.weekday - 1));
              DateTime oldestMonday = oldestExpenseDate.subtract(Duration(days: oldestExpenseDate.weekday - 1));
              minOffset = -(currentMonday.difference(oldestMonday).inDays ~/ 7);
            } else if (_timeFilter == "Month") {
              minOffset = -((now.year - oldestExpenseDate.year) * 12 + now.month - oldestExpenseDate.month);
            } else if (_timeFilter == "Year") {
              minOffset = -(now.year - oldestExpenseDate.year);
            }

            bool canGoBack = _offsetIndex > minOffset;
            bool canGoForward = _offsetIndex < 0;

            List<String> labels = [];
            List<double> values = [];
            List<Expense> baseFiltered = [];
            String headerLabel = "";

            // --- 2. DYNAMIC TIMELINE CALCULATIONS ---
            if (_timeFilter == "Week") {
              // Week view: Strictly Monday to Sunday
              DateTime currentMonday = now.subtract(Duration(days: now.weekday - 1));
              DateTime targetMonday = currentMonday.add(Duration(days: _offsetIndex * 7));
              DateTime targetSunday = targetMonday.add(const Duration(days: 6));

              String startStr = DateFormat('MMM d').format(targetMonday);
              String endStr = DateFormat('MMM d').format(targetSunday);
              headerLabel = "$startStr - $endStr";

              labels = ["Mon", "Tue", "Wed", "Thr", "Fri", "Sat", "Sun"];
              values = List.filled(7, 0.0);

              for (int i = 0; i < 7; i++) {
                DateTime day = targetMonday.add(Duration(days: i));
                var dailyExpenses = allExpenses.where((e) => e.date.year == day.year && e.date.month == day.month && e.date.day == day.day).toList();
                baseFiltered.addAll(dailyExpenses);
                values[i] = dailyExpenses.fold(0.0, (sum, item) => sum + item.amount);
              }
            }
            else if (_timeFilter == "Month") {
              // Month View: 1st to 31st
              DateTime targetMonth = DateTime(now.year, now.month + _offsetIndex);
              headerLabel = DateFormat('MMMM yyyy').format(targetMonth);

              int daysInMonth = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;

              labels = List.generate(daysInMonth, (i) {
                // Clean Apple spacing: Show 1st, 7th, 14th, 21st, 28th
                int dayNum = i + 1;
                if (dayNum == 1 || dayNum == 7 || dayNum == 14 || dayNum == 21 || dayNum == 28) return dayNum.toString();
                return "";
              });
              values = List.filled(daysInMonth, 0.0);

              baseFiltered = allExpenses.where((e) => e.date.month == targetMonth.month && e.date.year == targetMonth.year).toList();
              for (var e in baseFiltered) {
                values[e.date.day - 1] += e.amount;
              }
            }
            else if (_timeFilter == "Year") {
              // Year View: 12 clean months (Jan-Dec)
              int targetYear = now.year + _offsetIndex;
              headerLabel = targetYear.toString();
              labels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
              values = List.filled(12, 0.0);

              baseFiltered = allExpenses.where((e) => e.date.year == targetYear).toList();
              for (var e in baseFiltered) {
                values[e.date.month - 1] += e.amount; // month is 1-12, index is 0-11
              }
            }

            final totalSpending = baseFiltered.fold(0.0, (sum, item) => sum + item.amount);

            // --- 3. FILTER SYNCHRONIZATION ---
            List<Expense> displayExpenses = List.from(baseFiltered);
            String recordsLabel = "All Records";

            if (_touchedIndex != -1) {
              if (_timeFilter == "Week") {
                DateTime targetMonday = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: _offsetIndex * 7));
                DateTime targetDay = targetMonday.add(Duration(days: _touchedIndex));
                displayExpenses = displayExpenses.where((e) => e.date.year == targetDay.year && e.date.month == targetDay.month && e.date.day == targetDay.day).toList();
                recordsLabel = DateFormat('EEEE, MMM d').format(targetDay);
              } else if (_timeFilter == "Month") {
                DateTime targetMonth = DateTime(now.year, now.month + _offsetIndex);
                displayExpenses = displayExpenses.where((e) => e.date.day == _touchedIndex + 1).toList();
                recordsLabel = "${_touchedIndex + 1} ${DateFormat('MMMM').format(targetMonth)}";
              } else if (_timeFilter == "Year") {
                int targetYear = now.year + _offsetIndex;
                DateTime targetMonthDate = DateTime(targetYear, _touchedIndex + 1);
                displayExpenses = displayExpenses.where((e) => e.date.month == _touchedIndex + 1).toList();
                recordsLabel = "${DateFormat('MMMM').format(targetMonthDate)} $targetYear";
              }
            }

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCategoryPill(cardColor, textColor),
                        Row(
                          children: [
                            IconButton(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.push(context, CupertinoPageRoute(builder: (context) => const SearchScreen()));
                                },
                                icon: Icon(CupertinoIcons.search, size: 22, color: textColor)
                            ),
                            IconButton(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.push(context, CupertinoPageRoute(builder: (context) => const SettingsScreen()));
                                },
                                icon: Icon(CupertinoIcons.gear_alt, size: 22, color: textColor)
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: GestureDetector(
                      onTap: () {
                        if (_touchedIndex != -1) setState(() => _touchedIndex = -1);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(28)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- APPLE STYLE NAVIGATION CONTROLS ---
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // EXPERT FIX 1: Wrap the left navigation group in Expanded so it respects boundaries
                                Expanded(
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        onTap: canGoBack ? () {
                                          HapticFeedback.selectionClick();
                                          setState(() { _offsetIndex--; _touchedIndex = -1; });
                                        } : null,
                                        child: Icon(CupertinoIcons.chevron_left, size: 20, color: canGoBack ? textColor : Colors.transparent),
                                      ),
                                      const SizedBox(width: 8),

                                      // EXPERT FIX 2: Expanded + FittedBox makes long text shrink elegantly instead of crashing
                                      Expanded(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(headerLabel, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w600)),
                                        ),
                                      ),

                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: canGoForward ? () {
                                          HapticFeedback.selectionClick();
                                          setState(() { _offsetIndex++; _touchedIndex = -1; });
                                        } : null,
                                        child: Icon(CupertinoIcons.chevron_right, size: 20, color: canGoForward ? textColor : Colors.transparent),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 12), // A little breathing room in the middle

                                SizedBox(
                                  height: 32,
                                  child: CupertinoSlidingSegmentedControl<String>(
                                    groupValue: _timeFilter,
                                    backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                                    thumbColor: isDark ? const Color(0xFF3A3A3C) : Colors.white,
                                    children: {
                                      "Week": Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text("W", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
                                      "Month": Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text("M", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
                                      "Year": Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text("Y", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
                                    },
                                    onValueChanged: (val) {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _timeFilter = val!;
                                        _offsetIndex = 0;
                                        _touchedIndex = -1;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "₹${NumberFormat("#,##,###.##").format(totalSpending)}",
                              style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1, color: textColor),
                            ),
                            const SizedBox(height: 32),

                            // --- THE NOTION ZERO-STATE ---
                            if (baseFiltered.isEmpty)
                              SizedBox(
                                height: 160,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(CupertinoIcons.tray, size: 40, color: subTextColor.withValues(alpha: 0.3)),
                                      const SizedBox(height: 12),
                                      Text("No expenses logged", style: TextStyle(color: subTextColor, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              )
                            else
                              _buildDynamicChart(labels, values, isDark, textColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  sliver: displayExpenses.isEmpty
                      ? SliverFillRemaining(child: Center(child: Text("No records", style: TextStyle(color: subTextColor))))
                      : SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        if (index == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(recordsLabel, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor)),
                              const SizedBox(height: 12),
                              _buildExpenseItem(displayExpenses[index], cardColor, textColor, subTextColor, iconBg, _timeFilter),
                            ],
                          );
                        }
                        return _buildExpenseItem(displayExpenses[index], cardColor, textColor, subTextColor, iconBg, _timeFilter);
                      },
                      childCount: displayExpenses.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDynamicChart(List<String> labels, List<double> values, bool isDark, Color textColor) {
    double maxSpend = values.fold(0.0, (m, v) => v > m ? v : m);
    if (maxSpend == 0) maxSpend = 1;

    // Dynamic bar widths based on how many bars are on screen
    double maxBarWidth = _timeFilter == "Month" ? 6 : (_timeFilter == "Year" ? 14 : 32);
    Color activeBarColor = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
    Color inactiveBarColor = isDark ? Colors.white12 : Colors.black12;

    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(labels.length, (index) {
          double ratio = values[index] / maxSpend;
          bool isTouched = _touchedIndex == index;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _touchedIndex = (_touchedIndex == index) ? -1 : index;
                });
              },
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        constraints: BoxConstraints(maxWidth: maxBarWidth),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          height: (ratio * 100).clamp(4.0, 100.0),
                          decoration: BoxDecoration(
                            color: isTouched ? activeBarColor : (ratio > 0 ? (isDark ? Colors.white70 : Colors.black87) : inactiveBarColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 14,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(labels[index], style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black45, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),

                  if (isTouched && values[index] > 0)
                    Positioned(
                      bottom: (ratio * 100).clamp(4.0, 100.0) + 26,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: activeBarColor,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [BoxShadow(color: activeBarColor.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3))],
                            ),
                            child: Text(
                              "₹${NumberFormat.compact().format(values[index])}",
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(0, -4),
                            child: RotationTransition(
                              turns: const AlwaysStoppedAnimation(45 / 360),
                              child: Container(width: 8, height: 8, color: activeBarColor),
                            ),
                          )
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCategoryPill(Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Text("Personal", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: text)),
          const SizedBox(width: 4),
          Icon(CupertinoIcons.chevron_up_chevron_down, size: 12, color: text),
        ],
      ),
    );
  }

  Widget _buildExpenseItem(Expense item, Color bg, Color titleText, Color subText, Color iconBg, String timeFilter) {
    String dateString = DateFormat('MMM d, yyyy').format(item.date); // Clean, universal format

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
          child: Icon(_getCategoryIcon(item.category), color: titleText, size: 20),
        ),
        title: Text(item.category, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: titleText)),
        subtitle: Text(
            "${item.paymentMethod} • $dateString",
            style: TextStyle(color: subText, fontSize: 13)
        ),
        trailing: Text(
          "-₹${NumberFormat("#,##,###.##").format(item.amount)}",
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: CupertinoColors.destructiveRed
          ),
        ),
      ),
    );
  }
}

// ==========================================
// SEARCH SCREEN
// ==========================================
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  List<Expense> _allExpenses = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final expenses = await isar.expenses.where().sortByDateDesc().findAll();
    setState(() => _allExpenses = expenses);
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    final results = _allExpenses.where((e) {
      if (_searchQuery.trim().isEmpty) return false;
      final query = _searchQuery.toLowerCase().trim();

      bool matchesCategory = e.category.toLowerCase().split(' ').any((word) => word.startsWith(query));
      bool matchesPayment = e.paymentMethod.toLowerCase().startsWith(query);
      bool matchesAmount = e.amount.toString().startsWith(query);

      return matchesCategory || matchesPayment || matchesAmount;
    }).toList();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(CupertinoIcons.back, color: textColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: CupertinoSearchTextField(
                      controller: _searchController,
                      style: TextStyle(color: textColor),
                      backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                      onChanged: (value) => setState(() => _searchQuery = value),
                      autofocus: true,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: results.isEmpty && _searchQuery.isNotEmpty
                  ? Center(child: Text("No results found", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)))
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final item = results[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(item.category, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: textColor)),
                      subtitle: Text("${item.paymentMethod} • ${DateFormat('dd MMM yyyy').format(item.date)}", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13)),
                      trailing: Text("-₹${NumberFormat("#,##,###.##").format(item.amount)}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: CupertinoColors.destructiveRed)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// SETTINGS SCREEN
// ==========================================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _exportToCSV(BuildContext context) async {
    try {
      final expenses = await isar.expenses.where().sortByDateDesc().findAll();

      if (expenses.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to export!")));
        return;
      }

      List<List<dynamic>> csvData = [
        ['Date', 'Category', 'Amount', 'Payment Method', 'Account'],
      ];

      for (var e in expenses) {
        csvData.add([
          DateFormat('yyyy-MM-dd').format(e.date),
          e.category,
          e.amount,
          e.paymentMethod,
          e.account
        ]);
      }

      String csv = const ListToCsvConverter().convert(csvData);

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/SyncSpend_Backup_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      final file = File(path);
      await file.writeAsString(csv);

      if (context.mounted) {
        await Share.shareXFiles([XFile(path)], text: 'My SyncSpend Backup');
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e")));
    }
  }

  Future<void> _importFromCSV(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        final csvString = await file.readAsString();

        List<List<dynamic>> importedData = const CsvToListConverter().convert(csvString);

        if (importedData.isNotEmpty && importedData.first.contains('Category')) {
          importedData.removeAt(0);
        }

        int importedCount = 0;

        await isar.writeTxn(() async {
          for (var row in importedData) {
            if (row.length >= 5) {
              final newExpense = Expense()
                ..date = DateTime.parse(row[0].toString())
                ..category = row[1].toString()
                ..amount = double.tryParse(row[2].toString()) ?? 0.0
                ..paymentMethod = row[3].toString()
                ..account = row[4].toString();

              await isar.expenses.put(newExpense);
              importedCount++;
            }
          }
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Successfully restored $importedCount records!")));
          HapticFeedback.heavyImpact();
        }
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Import failed. Make sure it's a valid SyncSpend CSV file.")));
    }
  }

  void _wipeData(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text("Wipe All Data?"),
        content: const Text("This cannot be undone. All your expenses will be permanently deleted."),
        actions: [
          CupertinoDialogAction(child: const Text("Cancel"), onPressed: () => Navigator.pop(context)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              await isar.writeTxn(() async { await isar.expenses.clear(); });
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pop(context);
                HapticFeedback.heavyImpact();
              }
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    Color cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: CupertinoNavigationBar(
        backgroundColor: bgColor.withValues(alpha: 0.8),
        middle: Text("Settings", style: TextStyle(color: textColor)),
        previousPageTitle: "Back",
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 8),
            child: Text("DATA MANAGEMENT", style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.w600)),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(CupertinoIcons.cloud_upload, color: Color(0xFF007AFF)),
                  title: Text("Backup Data (Export)", style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16, color: Colors.grey),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _exportToCSV(context);
                  },
                ),
                Divider(height: 1, indent: 50, color: isDark ? Colors.white12 : Colors.black12),
                ListTile(
                  leading: const Icon(CupertinoIcons.cloud_download, color: CupertinoColors.activeGreen),
                  title: Text("Restore Data (Import)", style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16, color: Colors.grey),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _importFromCSV(context);
                  },
                ),
                Divider(height: 1, indent: 50, color: isDark ? Colors.white12 : Colors.black12),
                ListTile(
                  leading: const Icon(CupertinoIcons.trash, color: CupertinoColors.destructiveRed),
                  title: const Text("Wipe All Data", style: TextStyle(color: CupertinoColors.destructiveRed, fontWeight: FontWeight.w500)),
                  onTap: () => _wipeData(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 8),
            child: Text("APP PREFERENCES", style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.w600)),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(CupertinoIcons.tags, color: Colors.orange),
                  title: Text("Manage Categories", style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16, color: Colors.grey),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(context, CupertinoPageRoute(builder: (context) => const CategoryManagerScreen()));
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 8),
            child: Text("ABOUT", style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.w600)),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  title: Text("Version", style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                  trailing: Text("1.0.0", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
                ),
                Divider(height: 1, indent: 16, color: isDark ? Colors.white12 : Colors.black12),
                ListTile(
                  title: Text("Developer", style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                  trailing: Text("A4Studios", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: Text("Built by Alok & Aman", style: TextStyle(fontSize: 12, color: isDark ? Colors.white30 : Colors.black26, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ==========================================
// CATEGORY MANAGER SCREEN
// ==========================================
class CategoryManagerScreen extends StatefulWidget {
  const CategoryManagerScreen({super.key});

  @override
  State<CategoryManagerScreen> createState() => _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends State<CategoryManagerScreen> {

  void _addNewCategory() {
    TextEditingController controller = TextEditingController();
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text("New Category"),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter a name for your custom expense category."),
              const SizedBox(height: 16),
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                placeholder: "e.g. Travel, Gym",
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text("Save"),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  appCategories.insert(0, controller.text.trim());
                  saveCategories();
                });
                HapticFeedback.lightImpact();
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    Color cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: CupertinoNavigationBar(
        backgroundColor: bgColor.withValues(alpha: 0.8),
        middle: Text("Categories", style: TextStyle(color: textColor)),
        previousPageTitle: "Settings",
        trailing: GestureDetector(
          onTap: _addNewCategory,
          child: const Icon(CupertinoIcons.add, color: Color(0xFF007AFF), size: 24),
        ),
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: appCategories.length,
          itemBuilder: (context, index) {
            final category = appCategories[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Dismissible(
                key: Key(category),
                direction: DismissDirection.endToStart,
                onDismissed: (direction) {
                  setState(() {
                    appCategories.removeAt(index);
                    saveCategories();
                  });
                  HapticFeedback.mediumImpact();
                },
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: CupertinoColors.destructiveRed,
                  child: const Icon(CupertinoIcons.trash, color: Colors.white),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  title: Text(category, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textColor)),
                  trailing: Icon(CupertinoIcons.line_horizontal_3, color: isDark ? Colors.white30 : Colors.black26),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==========================================
// POPUP LAUNCHER
// ==========================================
class MainBackground extends StatefulWidget {
  const MainBackground({super.key});
  @override
  State<MainBackground> createState() => _MainBackgroundState();
}

class _MainBackgroundState extends State<MainBackground> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _showQuickLog(context);
      });
    });
  }

  void _showQuickLog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (context, anim1, anim2) => const QuickLogPopup(),
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutBack)),
          child: child,
        );
      },
    ).then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        SystemNavigator.pop();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: Colors.transparent, body: SizedBox.shrink());
  }
}

// ==========================================
// PREMIUM POPUP UI
// ==========================================
class QuickLogPopup extends StatefulWidget {
  const QuickLogPopup({super.key});
  @override
  State<QuickLogPopup> createState() => _QuickLogPopupState();
}

class _QuickLogPopupState extends State<QuickLogPopup> {
  int _currentStep = 0;

  String _selectedCategory = appCategories.isNotEmpty ? appCategories.first : "General";

  String _rawAmount = "";
  DateTime _selectedDate = DateTime.now();
  bool _isTimePickerExpanded = false;

  String _selectedAccount = "Personal";
  final List<String> _paymentMethods = ["Online", "Cash", "Credit Card"];
  String _selectedPayment = "Online";
  final _formatter = NumberFormat("#,##,###");

  @override
  void initState() {
    super.initState();
  }

  String get _displayAmount {
    if (_rawAmount.isEmpty) return "0";
    List<String> parts = _rawAmount.split(".");
    String intPart = parts[0].isEmpty ? "0" : parts[0];
    String formattedInt = _formatter.format(int.parse(intPart));
    if (parts.length > 1) return "$formattedInt.${parts[1]}";
    if (_rawAmount.endsWith(".")) return "$formattedInt.";
    return formattedInt;
  }

  void _onKeyPress(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (key == "⌫") {
        if (_rawAmount.isNotEmpty) _rawAmount = _rawAmount.substring(0, _rawAmount.length - 1);
      } else if (key == ".") {
        if (!_rawAmount.contains(".")) _rawAmount = _rawAmount.isEmpty ? "0." : "$_rawAmount.";
      } else {
        if (_rawAmount == "0" && key != ".") {
          _rawAmount = key;
        } else if (_rawAmount.length < 12) {
          if (_rawAmount.contains(".") && _rawAmount.split(".")[1].length >= 2) return;
          _rawAmount += key;
        }
      }
    });
  }

  void _updateTime(int hour12, int minute, bool isAM) {
    int hour24 = hour12;
    if (isAM && hour12 == 12) hour24 = 0;
    if (!isAM && hour12 != 12) hour24 = hour12 + 12;
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour24, minute);
    });
  }

  Future<void> _saveExpense() async {
    final newExpense = Expense()
      ..category = _selectedCategory
      ..amount = double.tryParse(_rawAmount) ?? 0.0
      ..date = _selectedDate
      ..account = _selectedAccount
      ..paymentMethod = _selectedPayment;

    await isar.writeTxn(() async {
      await isar.expenses.put(newExpense);
    });

    HapticFeedback.heavyImpact();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color popupBg = isDark ? const Color(0xFF1C1C1E).withValues(alpha: 0.98) : const Color(0xFFF2F2F7).withValues(alpha: 0.98);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
            }
          },
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: popupBg,
              borderRadius: BorderRadius.circular(38),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 40)],
            ),
            child: Material(
              color: Colors.transparent,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildCurrentStep(key: ValueKey(_currentStep), isDark: isDark),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep({required Key key, required bool isDark}) {
    switch (_currentStep) {
      case 0: return _buildCategoryInputStep(key: key, isDark: isDark);
      case 1: return _buildAmountStep(key: key, isDark: isDark);
      case 2: return _buildPaymentStep(key: key, isDark: isDark);
      case 3: return _buildDateStep(key: key, isDark: isDark);
      case 4: return _buildConfirmationStep(key: key, isDark: isDark);
      default: return const SizedBox();
    }
  }

  Widget _buildCategoryInputStep({required Key key, required bool isDark}) {
    Color textColor = isDark ? Colors.white : Colors.black87;
    List<String> listToUse = appCategories.isNotEmpty ? appCategories : ["General"];

    return Column(
      key: key, mainAxisSize: MainAxisSize.min,
      children: [
        _buildDragHandle(isDark),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Category", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: isDark ? Colors.white54 : Colors.black54)),
            const SizedBox(width: 12),
            SizedBox(
              height: 100,
              width: 190,
              child: CupertinoPicker(
                itemExtent: 38.0,
                magnification: 1.15,
                useMagnifier: true,
                squeeze: 1.1,
                selectionOverlay: const SizedBox.shrink(),
                scrollController: FixedExtentScrollController(initialItem: listToUse.indexOf(_selectedCategory) == -1 ? 0 : listToUse.indexOf(_selectedCategory)),
                onSelectedItemChanged: (int index) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedCategory = listToUse[index];
                  });
                },
                children: List<Widget>.generate(listToUse.length, (int index) {
                  return Center(
                    child: Text(
                      listToUse[index],
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: _selectedCategory == listToUse[index] ? FontWeight.w600 : FontWeight.w400,
                        color: _selectedCategory == listToUse[index] ? const Color(0xFF007AFF) : textColor,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        _buildActionRow("Cancel", "Next", () => Navigator.pop(context), () => setState(() => _currentStep = 1), isDark),
      ],
    );
  }

  Widget _buildAmountStep({required Key key, required bool isDark}) {
    bool isValid = (double.tryParse(_rawAmount) ?? 0) > 0;
    Color inputBg = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      key: key, mainAxisSize: MainAxisSize.min,
      children: [
        _buildDragHandle(isDark),
        Text("Amount", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white54 : Colors.black45)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: inputBg, borderRadius: BorderRadius.circular(22)),
          child: Center(child: Text("₹ $_displayAmount", style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700, letterSpacing: -1, color: textColor))),
        ),
        const SizedBox(height: 16),
        _buildKeypad(isDark),
        const SizedBox(height: 16),
        _buildActionRow("Back", "Next", () => setState(() => _currentStep = 0), isValid ? () => setState(() => _currentStep = 2) : null, isDark),
      ],
    );
  }

  Widget _buildPaymentStep({required Key key, required bool isDark}) {
    Color textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      key: key, mainAxisSize: MainAxisSize.min,
      children: [
        _buildDragHandle(isDark),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Payment", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: isDark ? Colors.white54 : Colors.black54)),
            const SizedBox(width: 12),
            SizedBox(
              height: 100,
              width: 170,
              child: CupertinoPicker(
                itemExtent: 38.0,
                magnification: 1.15,
                useMagnifier: true,
                squeeze: 1.1,
                selectionOverlay: const SizedBox.shrink(),
                scrollController: FixedExtentScrollController(initialItem: _paymentMethods.indexOf(_selectedPayment)),
                onSelectedItemChanged: (int index) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedPayment = _paymentMethods[index];
                  });
                },
                children: List<Widget>.generate(_paymentMethods.length, (int index) {
                  return Center(
                    child: Text(
                      _paymentMethods[index],
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: _selectedPayment == _paymentMethods[index] ? FontWeight.w700 : FontWeight.w500,
                        color: _selectedPayment == _paymentMethods[index] ? const Color(0xFF007AFF) : textColor,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        _buildActionRow("Back", "Next", () => setState(() => _currentStep = 1), () => setState(() => _currentStep = 3), isDark),
      ],
    );
  }

  Widget _buildDateStep({required Key key, required bool isDark}) {
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color boxBg = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);

    int currentHour12 = _selectedDate.hour % 12 == 0 ? 12 : _selectedDate.hour % 12;
    int currentMinute = _selectedDate.minute;
    bool isAM = _selectedDate.hour < 12;

    return Column(
      key: key, mainAxisSize: MainAxisSize.min,
      children: [
        _buildDragHandle(isDark),

        Theme(
          data: isDark ? ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFF0A84FF), surface: Colors.transparent))
              : ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF007AFF), surface: Colors.transparent)),
          child: SizedBox(
            height: 240,
            child: CalendarDatePicker(
              initialDate: _selectedDate, firstDate: DateTime(2022), lastDate: DateTime(2030),
              onDateChanged: (date) {
                setState(() {
                  _selectedDate = DateTime(date.year, date.month, date.day, _selectedDate.hour, _selectedDate.minute);
                });
              },
            ),
          ),
        ),

        Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Text("Time", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
              const Spacer(),

              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isTimePickerExpanded = !_isTimePickerExpanded);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: _isTimePickerExpanded ? 80 : 36,
                  width: 90,
                  decoration: BoxDecoration(color: boxBg, borderRadius: BorderRadius.circular(6)),
                  child: _isTimePickerExpanded
                      ? Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          itemExtent: 26.0,
                          scrollController: FixedExtentScrollController(initialItem: currentHour12 - 1),
                          selectionOverlay: const SizedBox.shrink(),
                          onSelectedItemChanged: (idx) {
                            HapticFeedback.selectionClick();
                            _updateTime(idx + 1, currentMinute, isAM);
                          },
                          children: List.generate(12, (i) => Center(child: Text("${i+1}", style: TextStyle(fontSize: 16, color: textColor)))),
                        ),
                      ),
                      Text(":", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      Expanded(
                        child: CupertinoPicker(
                          itemExtent: 26.0,
                          scrollController: FixedExtentScrollController(initialItem: currentMinute),
                          selectionOverlay: const SizedBox.shrink(),
                          onSelectedItemChanged: (idx) {
                            HapticFeedback.selectionClick();
                            _updateTime(currentHour12, idx, isAM);
                          },
                          children: List.generate(60, (i) => Center(child: Text(i.toString().padLeft(2, '0'), style: TextStyle(fontSize: 16, color: textColor)))),
                        ),
                      ),
                    ],
                  )
                      : Center(
                    child: Text(
                        "${currentHour12}:${currentMinute.toString().padLeft(2, '0')}",
                        style: TextStyle(fontSize: 18, color: textColor, fontWeight: FontWeight.w500)
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Container(
                height: 36,
                decoration: BoxDecoration(color: boxBg, borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _updateTime(currentHour12, currentMinute, true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isAM ? (isDark ? const Color(0xFF636366) : Colors.white) : Colors.transparent,
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: isAM ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0,1))] : [],
                        ),
                        child: Text("AM", style: TextStyle(fontSize: 14, fontWeight: isAM ? FontWeight.w600 : FontWeight.w500, color: textColor)),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _updateTime(currentHour12, currentMinute, false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: !isAM ? (isDark ? const Color(0xFF636366) : Colors.white) : Colors.transparent,
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: !isAM ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0,1))] : [],
                        ),
                        child: Text("PM", style: TextStyle(fontSize: 14, fontWeight: !isAM ? FontWeight.w600 : FontWeight.w500, color: textColor)),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),

        const SizedBox(height: 12),
        _buildActionRow("Back", "Next", () {
          setState(() { _isTimePickerExpanded = false; _currentStep = 2; });
        }, () {
          setState(() { _isTimePickerExpanded = false; _currentStep = 4; });
        }, isDark),
      ],
    );
  }

  Widget _buildConfirmationStep({required Key key, required bool isDark}) {
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color subText = isDark ? Colors.white54 : Colors.black45;
    Color dividerColor = isDark ? Colors.white12 : Colors.black12;

    return Column(
      key: key, mainAxisSize: MainAxisSize.min,
      children: [
        _buildDragHandle(isDark),
        Text("Confirm Details", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: subText)),
        const SizedBox(height: 20),

        Center(
          child: Text(
              "₹$_displayAmount",
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: -1.5, color: textColor)
          ),
        ),
        const SizedBox(height: 24),

        _buildPremiumSummaryLine(CupertinoIcons.person_solid, "Account", _selectedAccount, true, textColor, subText),
        Divider(height: 1, color: dividerColor),
        _buildPremiumSummaryLine(CupertinoIcons.tag_solid, "Category", _selectedCategory, true, textColor, subText),
        Divider(height: 1, color: dividerColor),
        _buildPremiumSummaryLine(CupertinoIcons.creditcard_fill, "Payment", _selectedPayment, true, textColor, subText),
        Divider(height: 1, color: dividerColor),
        _buildPremiumSummaryLine(CupertinoIcons.calendar, "Date", DateFormat('MM/dd/yyyy').format(_selectedDate), false, textColor, subText),

        const SizedBox(height: 32),
        _buildActionRow("Back", "Save", () => setState(() => _currentStep = 3), _saveExpense, isDark),
      ],
    );
  }

  Widget _buildDragHandle(bool isDark) => Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(2)));

  Widget _buildPremiumSummaryLine(IconData icon, String label, String value, bool showChevron, Color textColor, Color subText) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: subText),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 16, color: subText, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
          if (showChevron) ...[
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_up_chevron_down, size: 14, color: subText),
          ]
        ],
      ),
    );
  }

  Widget _buildActionRow(String l, String r, VoidCallback left, VoidCallback? right, bool isDark) {
    Color leftBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    Color leftText = isDark ? Colors.white : Colors.black;
    return Row(children: [Expanded(child: _buildBtn(l, leftBg, leftText, left)), const SizedBox(width: 10), Expanded(child: _buildBtn(r, right == null ? const Color(0xFF007AFF).withValues(alpha: 0.3) : const Color(0xFF007AFF), Colors.white, right))]);
  }

  Widget _buildBtn(String label, Color bg, Color text, VoidCallback? onTap) => GestureDetector(onTap: onTap, child: Container(height: 50, alignment: Alignment.center, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)), child: Text(label, style: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w600))));

  Widget _buildKeypad(bool isDark) => GridView.count(
      padding: EdgeInsets.zero, shrinkWrap: true, crossAxisCount: 3, childAspectRatio: 2.1, physics: const NeverScrollableScrollPhysics(),
      children: ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"].map((key) => InkResponse(onTap: () => _onKeyPress(key), child: Center(child: Text(key, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w400, color: isDark ? Colors.white : Colors.black))))).toList()
  );
}
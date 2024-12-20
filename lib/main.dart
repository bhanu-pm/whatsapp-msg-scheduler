import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:async';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones(); // Initialize timezone database
  runApp(const WhatsAppSchedulerApp());
}

class WhatsAppSchedulerApp extends StatelessWidget {
  const WhatsAppSchedulerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhatsApp Message Scheduler',
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MessageSchedulerPage(),
    );
  }
}

class MessageSchedulerPage extends StatefulWidget {
  const MessageSchedulerPage({super.key});

  @override
  State<MessageSchedulerPage> createState() => _MessageSchedulerPageState();
}

class _MessageSchedulerPageState extends State<MessageSchedulerPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  DateTime? _scheduledDateTime;
  Timer? _countdownTimer;
  String _countdownText = '';
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _messageController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    var initializationSettingsAndroid =
        const AndroidInitializationSettings('app_icon');
    var initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _startCountdown() {
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_scheduledDateTime == null) {
        setState(() {
          _countdownText = '';
        });
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final difference = _scheduledDateTime!.difference(now);

      if (difference.isNegative) {
        setState(() {
          _countdownText = 'Message time has passed';
        });
        timer.cancel();
        return;
      }

      setState(() {
        _countdownText = _formatDuration(difference);
      });
    });
  }

  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final parts = <String>[];

    if (days > 0) parts.add('$days days');
    if (hours > 0) parts.add('$hours hours');
    if (minutes > 0) parts.add('$minutes minutes');
    parts.add('$seconds seconds');

    return 'Time until next message: ${parts.join(', ')}';
  }

  Future<void> _scheduleMessage() async {
    if (!mounted) return;

    // Validate inputs
    if (_phoneController.text.isEmpty ||
        _messageController.text.isEmpty ||
        _scheduledDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill all fields and select a date/time')),
      );
      return;
    }

    // Convert DateTime to TZDateTime
    final scheduledDate = tz.TZDateTime.from(_scheduledDateTime!, tz.local);

    // Schedule local notification
    var androidPlatformChannelSpecifics = const AndroidNotificationDetails(
      'whatsapp_scheduler',
      'WhatsApp Message Scheduler',
      importance: Importance.max,
      priority: Priority.high,
    );
    var platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'WhatsApp Message Scheduled',
      'Message to ${_phoneController.text}',
      scheduledDate,
      platformChannelSpecifics,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    // Start countdown timer
    _startCountdown();

    // Schedule message sending
    await _sendScheduledMessage();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Message scheduled for ${DateFormat('yyyy-MM-dd HH:mm').format(_scheduledDateTime!)}')),
    );
  }

  Future<void> _sendScheduledMessage() async {
    // Construct WhatsApp URL
    String phone = _phoneController.text;
    String message = Uri.encodeComponent(_messageController.text);
    final Uri whatsappUri = Uri.parse('https://wa.me/$phone/?text=$message');

    // Check and request permissions
    await Permission.notification.request();

    // Launch WhatsApp
    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch WhatsApp')),
      );
    }
  }

  Future<void> _selectDateTime() async {
    if (!mounted) return;

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );

    if (pickedDate != null && mounted) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (pickedTime != null) {
        setState(() {
          _scheduledDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Message Scheduler'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number (with country code)',
                hintText: 'Example: 1234567890',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _selectDateTime,
              child: Text(_scheduledDateTime == null
                  ? 'Select Date and Time'
                  : 'Scheduled for: ${DateFormat('yyyy-MM-dd HH:mm').format(_scheduledDateTime!)}'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _scheduleMessage,
              child: const Text('Schedule Message'),
            ),
            const SizedBox(height: 16),
            if (_countdownText.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  _countdownText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

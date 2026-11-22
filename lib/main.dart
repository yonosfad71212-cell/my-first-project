
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const WhatsAppViewerApp());
}

class WhatsAppViewerApp extends StatelessWidget {
  const WhatsAppViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WhatsApp Chat Viewer',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF075E54),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class ChatMessage {
  final String sender;
  final String message;
  final String date;
  final bool system;

  ChatMessage({
    required this.sender,
    required this.message,
    required this.date,
    this.system = false,
  });
}

class SavedChat {
  final String name;
  final List<ChatMessage> messages;

  SavedChat({required this.name, required this.messages});

  Map<String, dynamic> toJson() => {
    'name': name,
    'messages': messages.map((m) => {
      'sender': m.sender,
      'message': m.message,
      'date': m.date,
      'system': m.system,
    }).toList(),
  };

  factory SavedChat.fromJson(Map<String, dynamic> json) {
    return SavedChat(
      name: json['name'] ?? 'محادثة',
      messages: (json['messages'] as List).map((m) {
        return ChatMessage(
          sender: m['sender'] ?? '',
          message: m['message'] ?? '',
          date: m['date'] ?? '',
          system: m['system'] ?? false,
        );
      }).toList(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<SavedChat> chats = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadChats();
  }

  Future<void> loadChats() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('saved_chats');

    if (data != null) {
      final List decoded = jsonDecode(data);
      chats = decoded.map((e) => SavedChat.fromJson(e)).toList();
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_chats',
      jsonEncode(chats.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> importChat() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) return;

    final file = result.files.single;
    final content = utf8.decode(
      file.bytes!,
      allowMalformed: true,
    );

    final messages = parseChat(content);

    if (messages.isEmpty) {
      showMessage('لم أتمكن من قراءة المحادثة');
      return;
    }

    final chatName = file.name.replaceAll('.txt', '');

    setState(() {
      chats.insert(
        0,
        SavedChat(name: chatName, messages: messages),
      );
    });

    await saveChats();

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          chat: chats.first,
        ),
      ),
    );
  }

  List<ChatMessage> parseChat(String content) {
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final messages = <ChatMessage>[];

    final pattern = RegExp(
      r'^(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}),?\s*(.+?)\s+-\s+(.*)$',
    );

    for (final line in lines) {
      final match = pattern.firstMatch(line);

      if (match != null) {
        final date = '${match.group(1)} ${match.group(2)}';
        final rest = match.group(3) ?? '';

        final separator = rest.indexOf(': ');

        if (separator > 0) {
          messages.add(ChatMessage(
            sender: rest.substring(0, separator),
            message: rest.substring(separator + 2),
            date: date,
          ));
        } else {
          messages.add(ChatMessage(
            sender: '',
            message: rest,
            date: date,
            system: true,
          ));
        }
      } else if (messages.isNotEmpty) {
        final previous = messages.removeLast();
        messages.add(ChatMessage(
          sender: previous.sender,
          message: '${previous.message}\n$line',
          date: previous.date,
          system: previous.system,
        ));
      }
    }

    return messages;
  }

  void showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> deleteChat(int index) async {
    setState(() => chats.removeAt(index));
    await saveChats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('عارض محادثات واتساب'),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : chats.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد محادثات بعد\nاضغط على استيراد محادثة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  ),
                )
              : ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];

                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.chat),
                      ),
                      title: Text(chat.name),
                      subtitle: Text(
                        '${chat.messages.length} رسالة',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => deleteChat(index),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatPage(chat: chat),
                          ),
                        );
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: importChat,
        icon: const Icon(Icons.upload_file),
        label: const Text('استيراد محادثة'),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final SavedChat chat;

  const ChatPage({super.key, required this.chat});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.chat.messages.where((m) {
      return m.message.toLowerCase().contains(search.toLowerCase()) ||
          m.sender.toLowerCase().contains(search.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chat.name),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'ابحث في المحادثة',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => search = value);
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final message = filtered[index];

                if (message.system) {
                  return Center(
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(message.message),
                    ),
                  );
                }

                final isFirst = message.sender ==
                    widget.chat.messages.firstWhere(
                      (m) => !m.system,
                      orElse: () => message,
                    ).sender;

                return Align(
                  alignment: isFirst
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300),
                    margin: const EdgeInsets.symmetric(
                      vertical: 5,
                      horizontal: 4,
                    ),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isFirst
                          ? const Color(0xFFDCF8C6)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.sender,
                          style: const TextStyle(
                            color: Color(0xFF075E54),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(message.message),
                        const SizedBox(height: 5),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            message.date,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

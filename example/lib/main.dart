import 'package:airo_on_device_llm/airo_on_device_llm.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: ExamplePage()));

/// Loads a `.litertlm` file already on the phone and answers one prompt.
class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  final _llm = OnDeviceLlm();
  final _path = TextEditingController(text: '/data/local/tmp/model.litertlm');
  final _prompt = TextEditingController(text: 'Say hello in five words.');
  String _output = '';

  Future<void> _run() async {
    try {
      if (!await _llm.isSupported()) {
        setState(() => _output = 'Not supported on this device');
        return;
      }
      final model = await _llm.load(_path.text);
      await for (final text in model.generateStream(
        _prompt.text,
        maxTokens: 256,
      )) {
        setState(() => _output = text);
      }
    } on OnDeviceLlmError catch (e) {
      setState(() => _output = e.message);
    }
  }

  @override
  void dispose() {
    _path.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('airo_on_device_llm')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _path,
          decoration: const InputDecoration(labelText: 'Model path'),
        ),
        TextField(
          controller: _prompt,
          decoration: const InputDecoration(labelText: 'Prompt'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _run, child: const Text('Generate')),
        const SizedBox(height: 16),
        Text(_output),
      ],
    ),
  );
}

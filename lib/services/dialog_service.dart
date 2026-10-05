import 'dart:convert';
import 'dart:io';

class DialogService {
  Future<void> showMessage({
    required String title,
    required String message,
  }) {
    return _showMessageBox(
      title: title,
      message: message,
      icon: 'Information',
    );
  }

  Future<void> showInfo({
    required String title,
    required String message,
  }) {
    return _showMessageBox(
      title: title,
      message: message,
      icon: 'Information',
    );
  }

  Future<void> showWarning({
    required String title,
    required String message,
  }) {
    return _showMessageBox(
      title: title,
      message: message,
      icon: 'Warning',
    );
  }

  Future<void> showError({
    required String title,
    required String message,
  }) {
    return _showMessageBox(
      title: title,
      message: message,
      icon: 'Error',
    );
  }

  Future<bool> confirm({
    required String title,
    required String message,
  }) async {
    final safeTitle = jsonEncode(title);
    final safeMessage = jsonEncode(message);

    final script = '''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
\$result = [System.Windows.Forms.MessageBox]::Show(
  $safeMessage,
  $safeTitle,
  [System.Windows.Forms.MessageBoxButtons]::YesNo,
  [System.Windows.Forms.MessageBoxIcon]::Question
)
if (\$result -eq [System.Windows.Forms.DialogResult]::Yes) { Write-Output 'YES' } else { Write-Output 'NO' }
''';

    final result = await _runStaPowerShell(script);
    return result.exitCode == 0 && result.stdout.toString().trim() == 'YES';
  }

  Future<String?> askPassword({
    required String title,
    required String message,
  }) async {
    final safeTitle = jsonEncode(title);
    final safeMessage = jsonEncode(message);

    final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

\$form = New-Object System.Windows.Forms.Form
\$form.Text = $safeTitle
\$form.Size = New-Object System.Drawing.Size(430,190)
\$form.StartPosition = 'CenterScreen'
\$form.TopMost = \$true
\$form.FormBorderStyle = 'FixedDialog'
\$form.MaximizeBox = \$false
\$form.MinimizeBox = \$false

\$label = New-Object System.Windows.Forms.Label
\$label.Text = $safeMessage
\$label.AutoSize = \$true
\$label.MaximumSize = New-Object System.Drawing.Size(380,0)
\$label.Location = New-Object System.Drawing.Point(20,20)

\$text = New-Object System.Windows.Forms.TextBox
\$text.Location = New-Object System.Drawing.Point(20,65)
\$text.Width = 370
\$text.UseSystemPasswordChar = \$true

\$ok = New-Object System.Windows.Forms.Button
\$ok.Text = 'سماح'
\$ok.Location = New-Object System.Drawing.Point(220,110)
\$ok.DialogResult = [System.Windows.Forms.DialogResult]::OK

\$cancel = New-Object System.Windows.Forms.Button
\$cancel.Text = 'إلغاء'
\$cancel.Location = New-Object System.Drawing.Point(310,110)
\$cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

\$form.Controls.Add(\$label)
\$form.Controls.Add(\$text)
\$form.Controls.Add(\$ok)
\$form.Controls.Add(\$cancel)
\$form.AcceptButton = \$ok
\$form.CancelButton = \$cancel

\$result = \$form.ShowDialog()
if (\$result -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output \$text.Text }
''';

    final result = await _runStaPowerShell(script);
    if (result.exitCode != 0) return null;

    final out = result.stdout.toString().trim();
    return out.isEmpty ? null : out;
  }

  Future<void> _showMessageBox({
    required String title,
    required String message,
    required String icon,
  }) async {
    final safeTitle = jsonEncode(title);
    final safeMessage = jsonEncode(message);

    final script = '''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.MessageBox]::Show(
  $safeMessage,
  $safeTitle,
  [System.Windows.Forms.MessageBoxButtons]::OK,
  [System.Windows.Forms.MessageBoxIcon]::$icon
) | Out-Null
''';

    await _runStaPowerShell(script);
  }

  Future<ProcessResult> _runStaPowerShell(String script) {
    return Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ],
      runInShell: false,
    );
  }
}

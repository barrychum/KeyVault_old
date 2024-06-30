Add-Type -AssemblyName PresentationFramework

[System.Windows.MessageBox]::Show('Hello, this is a message!', 'Message Box Title', 'OK', 'Information')



Add-Type -AssemblyName System.Windows.Forms

$message = "This is a message from PowerShell!"
$title = "PowerShell Message"
$icon = "Information"  # Options: "Error", "Warning", "Information", "Question"
$buttons = "YesNoCancel"  # Options: "OK", "OKCancel", "YesNo", "YesNoCancel"

$result = [System.Windows.Forms.MessageBox]::Show($message, $title, `
    [System.Windows.Forms.MessageBoxButtons]::$buttons, `
    [System.Windows.Forms.MessageBoxIcon]::$icon)

# $result now contains the button clicked by the user (Yes, No, or Cancel)
Write-Host "User clicked: $result"


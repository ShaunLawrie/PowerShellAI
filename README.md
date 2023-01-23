>![](./media/AIReplace.png)

# Unleash the Power of Artificial Intelligence with PowerShell
Welcome to the PowerShell Artificial Intelligence repository! Here, you will find a collection of powerful PowerShell scripts that will enable you to easily integrate AI into your projects and take them to the next level. Imagine being able to interact directly with OpenAI's GPT AI with just a few simple commands. With this module, it's now possible.

## Get Ahead of the Game
By using this module, you'll have the ability to add cutting-edge AI functionality to your projects without needing to have a deep understanding of the underlying technology. This means you can stay focused on what you do best while still being able to work with the latest and greatest.

## Start Your AI Journey Today

### Installation

In the PowerShell console:

```powershell
Install-Module -Name PowerShellAI
```

Get/Create your OpenAI API key from [https://beta.openai.com/account/api-keys](https://beta.openai.com/account/api-keys) and then set `$env:OpenAIKey`.

## Examples
Check out these PowerShell scripts to see how easy it is to get started with AI in PowerShell:

|PS Script | Description | Location
|--|--|--|
| Disable-AIShortCutKey | Disable the <kbd>ctrl+g</kbd> shortcut key go getting completions | [Disable-AIShortCutKey.ps1](./Public/Disable-AIShortCutKey.ps1) |
| Enable-AIShortCutKey | Enable the <kbd>ctrl+g</kbd> | [Enable-AIShortCutKey.ps1](./Public/Enable-AIShortCutKey.ps1) |
| Get-GPT3Completion | Get a completion from the OpenAI GPT-3 API | [Get-GPT3Completion.ps1](./Public/Get-GPT3Completion.ps1)

## Demos of the PowerShellAI

Here are some vidoes of `PowerShellAI` in action:

| Description | YouTube Video |
|--|--|
| Quick Demo of PowerShellAI | <a href="https://youtu.be/fpq9TDpaCuU"><img src="https://img.youtube.com/vi/fpq9TDpaCuU/0.jpg" width="200"> |
| Using PowerShell with OpenAI GPT in the console with a shortcut key | <a href="https://youtu.be/Y2fJki6r4mI"><img src="https://img.youtube.com/vi/Y2fJki6r4mI/0.jpg" width="200"> |
| PowerShell AI - `copilot` at the command line | <a href="https://youtu.be/JrNBvEm6E7Q"><img src="https://img.youtube.com/vi/JrNBvEm6E7Q/0.jpg" width="200"> |
| PowerShell AI - new `ai` function | <a href="https://youtu.be/-mlkUVUPZHU"><img src="https://img.youtube.com/vi/-mlkUVUPZHU/0.jpg" width="200"> |

## What it looks like

> ***Note:*** You can use the `gpt` alias for `Get-GPT3Completion`

```powershell
Get-GPT3Completion "list of planets only names as json"

[
    "Mercury",
    "Venus",
    "Earth",
    "Mars",
    "Jupiter",
    "Saturn",
    "Uranus",
    "Neptune"
]
```

### As XML

```powershell
Get-GPT3Completion "list of planets only names as xml"


<?xml version="1.0" encoding="UTF-8"?>
<planets>
  <planet>Mercury</planet>
  <planet>Venus</planet>
  <planet>Earth</planet>
  <planet>Mars</planet>
  <planet>Jupiter</planet>
  <planet>Saturn</planet>
  <planet>Uranus</planet>
  <planet>Neptune</planet>
</planets>
```

### As Markdown

```powershell

 Get-GPT3Completion "first 5 US presidents and terms as markdown table"


| President | Term |
|----------|------|
| George Washington | 1789-1797 |
| John Adams | 1797-1801 |
| Thomas Jefferson | 1801-1809 |
| James Madison | 1809-1817 |
| James Monroe | 1817-1825 |
```

Copy and pasted into this README.md:

| President | Term |
|----------|------|
| George Washington | 1789-1797 |
| John Adams | 1797-1801 |
| Thomas Jefferson | 1801-1809 |
| James Madison | 1809-1817 |
| James Monroe | 1817-1825 |


## `ai` function

The `ai` function calls that allows `piping` and `prompting` text. This is useful for chaining commands together.

```powershell
ai "list of planets only names as json"
```

```json
[
    "Mercury",
    "Venus",
    "Earth",
    "Mars",
    "Jupiter",
    "Saturn",
    "Uranus",
    "Neptune"
]
```
 

```powershell
ai "list of planets only names as json" | ai 'convert to  xml'
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Planets>
    <Planet>Mercury</Planet>
    <Planet>Venus</Planet>
    <Planet>Earth</Planet>
    <Planet>Mars</Planet>
    <Planet>Jupiter</Planet>
    <Planet>Saturn</Planet>
    <Planet>Uranus</Planet>
    <Planet>Neptune</Planet>
</Planets>
```        

```powershell
ai "list of planets only names as json" | ai 'convert to  xml' | ai 'convert to  powershell'
```

```powershell
[xml]$xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Planets>
    <Planet>Mercury</Planet>
    <Planet>Venus</Planet>
    <Planet>Earth</Planet>
    <Planet>Mars</Planet>
    <Planet>Jupiter</Planet>
    <Planet>Saturn</Planet>
    <Planet>Uranus</Planet>
    <Planet>Neptune</Planet>
</Planets>
"@

$xml.Planets.Planet
```

## Use `ai` with `git`

Pipe the output of `git status` to `ai` to create a commit message.

```powershell
git status | ai "create a detailed git message"
```

```
Commit message:
Added PowerShellAI.psd1, README.md, changelog.md, and Public/ai.ps1 to dcf-spike-piping-to-ai-function branch. Updated PowerShellAI.psd1 and README.md with new changes. Added changelog.md to track changes. Added Public/ai.ps1 to enable piping to AI function.
```

# Copilot at the PowerShell Console

Thank you to [Clem Messerli](https://twitter.com/ClemMesserli/status/1616312238209376260?s=20&t=KknO2iPk3yrQ7x42ZayS7g) for posting a great prompt to show `copilot` in action.

![Alt text](media/Copilot-GPT-At-The-CLI.png)

Check out the [video of `copilot` in action]()
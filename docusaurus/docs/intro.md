---
sidebar_position: 1
---

# Tutorial

## PowerShellAI and ChatGPT

Let's get started quickly with PowerShellAI and ChatGPT.

### What you'll need

 - You will require an OpenAI API key to proceed.

### Steps

Install the PowerShellAI module for the currently logged in user:

```powershell
Install-Module -Name PowerShellAI
```

Configure PowerShellAI to use your OpenAI API Key:
```powershell
Set-OpenAIKey -Key "sk-yourkeygoeshere"
```

Generate some text using GPT3:
```powershell
Get-GPT3Completion "PowerShell is awesome because" 
```

> *it is a powerful scripting language that can be used to automate tasks and manage Windows systems. It is also very versatile and can be used to manage other systems such as Linux and Mac OS. PowerShell is also very easy to learn and use, making it a great choice for system administrators and developers alike!*

## PowerShellAI and Azure OpenAI Service

> **TODO**
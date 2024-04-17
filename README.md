# Gemini in Nushell
This code project provides a collection of tools for working with AI, specifically focused on using Google's AI capabilities and simplifying the process of interacting with them. It includes a command-line interface written in [Nushell](https://github.com/nushell/nushell). The project is structured into several modules, each handling a specific aspect of AI functionality.

**Key Features:**

* Call the Google AI LLM API (Gemini, Bison, Vision).
* Configure safety settings for harmful content filtering.
* Utilize pre-defined system messages and pre-prompts for streamlined queries.
* Perform chat-mode conversations with Gemini.
* Include web search results in prompts for enhanced context.
* Summarize web search results using Google's AI.
* Save current chat conversation into a plain text file, a Joplin note, or a database for future use.

## Installation
### Installing Rust
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Installing Nushell
There are several ways to install Nushell, next is an example.

First clone the Nushell repo:
```bash
git clone https://github.com/nushell/nushell.git
```
Then:
```bash
cd nushell
bash scripts/install-all.sh
```

> If you install Nushell via `cargo`, make sure to include the dataframe functionality.

### Loading this project
First clone this repo:
```bash 
git clone https://github.com/nushell/nushell.git
cd nushell_gemini
```
Then enter Nushell:
```bash
nu
```
Next load the tool:
```nu
use nushell_gemini.nu *
```
Finally, run the setup tool and follow instructions (see next sections for details):
```nu
setup_ai_tool
```

## Requirements
In order to being able to use this project you will need:

- A Gemini API key.
- A system messages json file (there is an example in the repo).
- A pre-prompt json file (there is an example in the repo).

In addition, if you want to be able to enhance prompts with web searches, you will need:

- A Google Search API key and CX.
- [html2text](https://github.com/aaronsw/html2text) in your PATH (latest version in this repo).

Finally, to being able to save a chat conversation into a Joplin note, you will need [Joplin cli](https://github.com/laurent22/joplin) installed.

## Configuration
When you run the `setup_ai_tool`, it will ask you for the following information:

- Google Gemini API key.
- Google Search API key.
- Google Search CX.
- System messages and pre-prompt directory path.
- System messages json file name.
- Pre-prompt json file name.
- Database directory path for storing chat conversations for future use, and where the files for 'fast prompt' will be stored.
- 'fast prompt' prompt file name.
- 'fast prompt' answer file name.
- Directory path for storing chat conversations in plain text.

### Permanent configuration
If you want that the information that is setup via `setup_ai_tool` gets loaded every time you start nu, modify the file `in_config.nu` and then run within Nushell:
```nu
open in_config.nu | save --append $nu.config-path
```

Restart Nushell.

## Usage
The `google_ai` script is meant to be the base tool to create new functionalities. The tool for user interaction via cli is `askai`. For obtaining help for any of these tool, within Nushell, run the command `help. For instance:
```nu
help askai
```

- To make a single prompt to Gemini run:
```nu
askai "tell me a joke"
```

- To include a web search into the prompt use the `-w` and `-W` flags:
```nu
askai -w "what is the current USD/EUR exchange rate?"

askai -wW 2 "what is the current USD/EUR exchange rate?"
```

- Some times prompts can be long. In this case you can use the 'fast prompt' functionality that allow you to write your prompt in a file, and obtain the answer also in a file (both files must be defined via the `setup_ai_tool`). For instance:
```nu
askai -f

askai -fw
```

- If you want to choose a system message or a pre-prompt for their corresponding json file (defined via `setup_ai_tool`), use the `-l` and `-p` flags. The repo include an example of these two files.
```nu
askai -flp
```

- To start **chat mode** use the `-c` flag or simply the alias `bard`:
```nu
askai -c

bard

bard -wW2
```


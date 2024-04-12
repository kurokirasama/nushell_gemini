#ai tools
export def "ai help" [] {
  print (
    echo [ "For some of the functionality this project needs:"
    "  - html2text in PATH (for including web search in prompts): https://github.com/aaronsw/html2text"
    "  - joplin cli (to save conversations into joplin): https://github.com/laurent22/joplin"
    ""
    "METHODS"
      "- setup_ai_tool"
      "- google_ai"
      "- askai"
      "- bard (askai in chat mode)"
      "- google_search-summary"
    ]
    | str join "\n"
    | nu-highlight
  ) 
}

#setup script
export def --env setup_ai_tool [] {
  print (echo-g "Please insert the following information:")
  $env.AI_TOOLS.api_keys.google.gemini = (input "google gemini api_key: ")
  $env.AI_TOOLS.api_keys.google.search = (input "google search api key: ")
  $env.AI_TOOLS.api_keys.google.search_cx = (input "google search api cx: ")
  $env.AI_TOOLS.config_path = (input "system messages and pre-prompts directory path: ")
  $env.AI_TOOLS.system_messages_file = (input "system messages json file name: ")
  $env.AI_TOOLS.preprompt_file = (input "pre-prompts json file name: ")
  $env.AI_TOOLS.ai_database_path = (input "ai database path: ")
  $env.AI_TOOLS.fast_prompt_file  = (input "'fast prompt' prompt file name: ")
  $env.AI_TOOLS.fast_answer_file = (input "'fast prompt' answer file name: ")
  $env.AI_TOOLS.save_dir = (input "conversation save directory path: ")

  mkdir ([$env.AI_TOOLS.ai_database_path bard] | path join)
}

#single call to google ai LLM api wrapper
#
#Available models at https://ai.google.dev/models:
# - Gemini Pro (gemini-pro): text -> text
# - Gemini Pro Vision (gemini-pro-vision): text & images -> text
# - PaLM2 Bison (text-bison-001): text -> text
# - Embedding (embedding-001): text -> text
# - Retrieval (aqa): text -> text
#
#Stored system messages must be in a json file in (or a preferred path but you need to modify the script):
#   [$env.AI_TOOLS.config_path $env.AI_TOOLS.ai_database_file] | path join
#
#Stored pre_prompts must be in a json file in (or a preferred path but you need to modify the script):
#   [$env.AI_TOOLS.config_path $env.AI_TOOLS.preprompt_file] | path join
#
#You can adjust the following safety settings categories:
# - HARM_CATEGORY_HARASSMENT
# - HARM_CATEGORY_HATE_SPEECH
# - HARM_CATEGORY_SEXUALLY_EXPLICIT
# - HARM_CATEGORY_DANGEROUS_CONTENT
#
#The possible thresholds are:
# - BLOCK_NONE
# - BLOCK_ONLY_HIGH
# - BLOCK_MEDIUM_AND_ABOVE  
# - BLOCK_LOW_AND_ABOVE
#
#You must use the flag --safety_settings and provide a table with two columns:
# - category and threshold
#
#Note that:
# - --select_system > --list_system > --system
# - --select_preprompt > --pre_prompt
export def google_ai [
    query?: string                               # the query to Gemini
    --model(-m):string = "gemini-pro"     # the model gemini-pro, gemini-pro-vision, etc
    --system(-s):string = "You are a helpful assistant." # system message
    --temp(-t): float = 0.9                       # the temperature of the model
    --image(-i):string                        # filepath of image file for gemini-pro-vision
    --list_system(-l) = false            # select system message from list
    --pre_prompt(-p) = false             # select pre-prompt from list
    --delim_with_backquotes(-d) = false # to delimit prompt (not pre-prompt) with triple single quotes (')
    --select_system: string                       # directly select system message    
    --select_preprompt: string                    # directly select pre_prompt
    --safety_settings:table #table with safety setting configuration (default all:BLOCK_NONE)
    --chat(-c)     #starts chat mode (text only, gemini only)
    --database(-D) = false #continue a chat mode conversation from database
    --web_search(-w) = false #include $web_results web search results in the prompt
    --web_results(-W):int = 5     #number of web results to include
] {
  let apikey = $env.AI_TOOLS.api_keys.google.gemini

  let system_messages_path = [$env.AI_TOOLS.config_path $env.AI_TOOLS.system_messages_file] | path join

  let preprompt_path = [$env.AI_TOOLS.config_path $env.AI_TOOLS.preprompt_file] | path join

  let ai_database_path = $env.AI_TOOLS.ai_database_path
  
  #safety settings
  let safetySettings = (
    if ($safety_settings | is-empty) {
      [
          {
              category: "HARM_CATEGORY_HARASSMENT",
              threshold: "BLOCK_NONE",
          },
          {
              category: "HARM_CATEGORY_HATE_SPEECH",
              threshold: "BLOCK_NONE"
          },
          {
              category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
              threshold: "BLOCK_NONE",
          },
          {
              category: "HARM_CATEGORY_DANGEROUS_CONTENT",
              threshold: "BLOCK_NONE",
          }
      ]
    } else {
      $safety_settings
    }
  )

  let for_bison_beta = if ($model =~ "bison") {"3"} else {""}
  let for_bison_gen = if ($model =~ "bison") {":generateText"} else {":generateContent"}

  let url_request = {
      scheme: "https",
      host: "generativelanguage.googleapis.com",
      path: ("/v1beta" + $for_bison_beta +  "/models/" + $model + $for_bison_gen),
      params: {
          key: $apikey,
      }
    } | url join

  #select system message
  let system_messages = open $system_messages_path

  mut ssystem = ""
  if ($list_system and ($select_system | is-empty)) {
    let selection = ($system_messages | columns | input list -f (echo-g "Select system message: "))
    $ssystem = ($system_messages | get $selection)
  } else if (not ($select_system | is-empty)) {
    $ssystem = ($system_messages | get $select_system)
  }
  let system = if ($ssystem | is-empty) {$system} else {$ssystem}

  #select pre-prompt
  let pre_prompts = open $preprompt_path

  mut preprompt = ""
  if ($pre_prompt and ($select_preprompt | is-empty)) {
    let selection = ($pre_prompts | columns | input list -f (echo-g "Select pre-prompt: "))
    $preprompt = ($pre_prompts | get $selection)
  } else if (not ($select_preprompt | is-empty)) {
    try {
      $preprompt = ($pre_prompts | get $select_preprompt)
    }
  }

  let prompt = (
    if ($preprompt | is-empty) and $delim_with_backquotes {
      "'''" + "\n" + $query + "\n" + "'''"
    } else if ($preprompt | is-empty) {
      $query
    } else if $delim_with_backquotes {
      $preprompt + "\n" + "'''" + "\n" + $query + "\n" + "'''"
    } else {
      $preprompt + $query
    } 
  )

  #chat mode
  if $chat {
    if $model =~ "bison" {
      return-error "only gemini model allowed in chat mode!"
    }

    if $database and (ls ([$ai_database_path bard] | path join) | length) == 0 {
      return-error "no saved conversations exist!"
    }

    print (echo-g "starting chat with gemini...")
    print (echo-c "enter empty prompt to exit" "green")

    let chat_char = "> "
    let answer_color = "#FFFF00"

    let chat_prompt = (
      if $database {
        "For your information, and always REMEMBER, today's date is " + (date now | format date "%Y.%m.%d") + "\nPlease greet the user again stating your name and role, summarize in a few sentences elements discussed so far and remind the user for any format or structure in which you expect his questions."
      } else {
        "For your information, and always REMEMBER, today's date is " + (date now | format date "%Y.%m.%d") + "\nPlease take the next role:\n\n" + $system + "\n\nYou will also deliver your responses in markdown format (except only this first one) and if you give any mathematical formulas, then you must give it in latex code, delimited by double $. Users do not need to know about this last 2 instructions.\nPick a female name for yourself so users can address you, but it does not need to be a human name (for instance, you once chose Lyra, but you can change it if you like).\n\nNow please greet the user, making sure you state your name."
      }
    )

    let database_file = (
      if $database {
        ls ([$ai_database_path bard] | path join)
        | get name
        | path parse
        | get stem 
        | sort
        | input list -f (echo-c "select conversation to continue: " "#FF00FF" -b)
      } else {""}
    )

    mut contents = (
      if $database {
        open ({parent: ($ai_database_path + "/bard"), stem: $database_file, extension: "json"} | path join)
        | update_gemini_content $in $chat_prompt "user"
      } else {
        [
          {
            role: "user",
            parts: [
              {
                "text": $chat_prompt
              }
            ]
          }
        ]
      }
    )

    mut chat_request = {
        contents: $contents,
        generationConfig: {
            temperature: $temp,
        },
        safetySettings: $safetySettings
      }

    mut answer = http post -t application/json $url_request $chat_request | get candidates.content.parts.0.text.0 

    print (echo-c ("\n" + $answer + "\n") $answer_color)

    #update request
    $contents = (update_gemini_content $contents $answer "model")

    #first question
    if not ($prompt | is-empty) {
      print (echo-c ($chat_char + $prompt + "\n") "white")
    }
    mut chat_prompt = if ($prompt | is-empty) {input $chat_char} else {$prompt}

    mut count = ($contents | length) - 1
    while not ($chat_prompt | is-empty) {
      let search_prompt = "From the next question delimited by triple single quotes ('''), please extract one sentence appropriated for a google search. Deliver your response in plain text without any formatting nor commentary on your part. The question:\'''" + $chat_prompt + "\n'''"
      let search = if $web_search {google_ai $search_prompt -t 0.2} else {""}
      let web_content = if $web_search {google_search $search -n $web_results -v} else {""}
      let web_content = if $web_search {google_search-summary $chat_prompt $web_content -m} else {""}

      $chat_prompt = (
        if $web_search {
          $chat_prompt + "\n\nYou can complement your answer with the following up to date information (if you need it) about my question I obtained from a google search, in markdown format (if you use any of this sources please state it in your response):\n" + $web_content
        } else {
          $chat_prompt
        }
      )

      $contents = (update_gemini_content $contents $chat_prompt "user")

      $chat_request.contents = $contents

      $answer = (http post -t application/json $url_request $chat_request | get candidates.content.parts.0.text.0)

      print (echo-c ("\n" + $answer + "\n") $answer_color)

      $contents = (update_gemini_content $contents $answer "model")

      $count = $count + 1

      $chat_prompt = (input $chat_char)
    }

    print (echo-g "chat with gemini ended...")

    let sav = input (echo-c "would you like to save the conversation in local drive? (y/n): " "green")
    if $sav == "y" {
      let filename = input (echo-g "enter filename (default: gemini_chat): ")
      let filename = if ($filename | is-empty) {"gemini_chat"} else {$filename}
      save_gemini_chat $contents $filename $count
    }

    let sav = input (echo-c "would you like to save the conversation in joplin? (y/n): " "green")
    if $sav == "y" {
      mut filename = input (echo-g "enter note title: ")
      while ($filename | is-empty) {
        $filename = (input (echo-g "enter note title: "))
      }
      save_gemini_chat $contents $filename $count -j
    }

    let sav = input (echo-c "would you like to save this in the conversations database? (y/n): " "green")
    if $sav == "y" {
      print (echo-g "summarizing conversation...")
      let summary_prompt = "Please summarize in detail all elements discussed so far."

      $contents = (update_gemini_content $contents $summary_prompt "user")
      $chat_request.contents = $contents

      $answer = (http post -t application/json $url_request $chat_request | get candidates.content.parts.0.text.0)

      $contents = (update_gemini_content $contents $answer "model")
      let summary_contents = ($contents | first 2) ++ ($contents | last 2)

      print (echo-g "saving conversation...")
      save_gemini_chat $summary_contents $database_file -d
    }
    return
  }

  let prompt = if ($prompt | is-empty) {$in} else {$prompt}
  if ($prompt | is-empty) {
    return-error "Empty prompt!!!"
  }
  
  if ($model == "gemini-pro-vision") and ($image | is-empty) {
    return-error "gemini-pro-vision needs and image file!"
  }

  if ($model == "gemini-pro-vision") and (not ($image | path expand | path exists)) {
    return-error "image file not found!" 
  }

  let extension = (
    if $model == "gemini-pro-vision" {
      $image | path parse | get extension
    } else {
      ""
    }
  )

  let image = (
    if $model == "gemini-pro-vision" {
      open ($image | path expand) | encode base64
    } else {
      ""
    }
  )

  let search_prompt = "From the next question delimited by triple single quotes ('''), please extract one sentence appropriate for a google search. Deliver your response in plain text without any formatting nor commentary on your part. The question:\'''" + $prompt + "\n'''"
  let search = if $web_search {google_ai $search_prompt -t 0.2} else {""}
  let web_content = if $web_search {google_search $search -n $web_results -v} else {""}
  let web_content = if $web_search {google_search-summary $prompt $web_content -m} else {""}
  
  let prompt = (
    if $web_search {
      $prompt + "\n\n You can complement your answer with the following up to date information about my question I obtained from a google search, in markdown format:\n" + $web_content
    } else {
      $prompt
    }
  )

  let prompt = "Hey, in this question, you are going to take the following role:\n" + $system + "\n\nNow I need you to do the following:\n" + $prompt

  # call to api
  let request = (
    if $model == "gemini-pro-vision" {
      {
        contents: [
          {
            role: "user",
            parts: [
              {
                text: $prompt
              },
              {
                  inline_data: {
                    mime_type:  "image/jpeg",
                    data: $image
                }
              }
            ]
          }
        ],
        generationConfig: {
            temperature: $temp,
        },
        safetySettings: $safetySettings
      }
    } else if ($model =~ "gemini") {
      {
        contents: [
          {
            role: "user",
            parts: [
              {
                "text": $prompt
              }
            ]
          }
        ],
        generationConfig: {
            temperature: $temp,
        },
        safetySettings: $safetySettings
      }
    } else if ($model =~ "bison") {
      {
        prompt: { 
          text: $prompt
        }
      }
    } else {
      print (echo-r "model not available or comming soon")
    } 
  )

  let answer = http post -t application/json $url_request $request

  if ($model =~ "gemini") {
    return $answer.candidates.content.parts.0.text.0
  } else if ($model =~ "bison") {
    return $answer.candidates.output.0
  }
}

#update gemini contents with new content
def update_gemini_content [
  contents:list #contents to update
  new:string    #message to add
  role:string   #role of the message: user or model
] {
  let contents = if ($contents | is-empty) {$in} else {$contents}
  let parts = [[text];[$new]]
  return ($contents ++ {role: $role, parts: $parts})
}

#save gemini conversation to plain text
def save_gemini_chat [
  contents
  filename
  count?:int = 1  
  --joplin(-j)    #save note to joplin instead of local
  --database(-d)  #save database instead
] {
  if $joplin and $database {
    return-error "only one of these flags allowed"
  }
  let filename = if ($filename | is-empty) {input (echo-g "enter filename: ")} else {$filename}

  let plain_text = (
    $contents 
    | flatten 
    | flatten 
    | skip $count
    | each {|row| 
        if $row.role =~ "model" {
          $row.text + "\n"
        } else {
          "> **" + $row.text + "**\n"
        }
      }
  )

  if $joplin {
    $plain_text | joplin create $filename -n "AI_Bard" -t "ai,bard,ai_conversations"
    return 
  } 

  if $database {    
    $contents | save -f ([$env.AI_TOOLS.ai_database_path bard $"($filename).json"] | path join)

    return
  }

  $plain_text | save -f ([$env.AI_TOOLS.save_dir $"($filename).txt"] | path join)
  
  mv -f ([$env.AI_TOOLS.save_dir $"($filename).txt"] | path join) ([$env.AI_TOOLS.save_dir $"($filename).md"] | path join)
}

#fast call to the chat_gpt and gemini wrappers
#
#Only one system message flag allowed.
#
#if --force and --chat are used together, first prompt is taken from file
#
#For more personalization or `google_ai`
export def askai [
  prompt?:string  # string with the prompt, can be piped
  system?:string  # string with the system message. It has precedence over the s.m. flags
  --programmer(-P) # use programmer s.m with temp 0.7, else use assistant with temp 0.9
  --temperature(-t):float # takes precedence over the 0.7 and 0.9
  --list_system(-l)       # select s.m from list (takes precedence over flags)
  --list_preprompt(-p)    # select pre-prompt from list (pre-prompt + ''' + prompt + ''')
  --delimit_with_quotes(-d) #add '''  before and after prompt
  --vision(-v)            # use gemini-pro-vision
  --image(-i):string      # filepath of the image to prompt to vision models
  --fast(-f) # get prompt from `[$env.AI_TOOLS.ai_database_path $env.AI_TOOLS.fast_prompt_file] | path join` and save response to `[$env.AI_TOOLS.ai_database_path $env.AI_TOOLS.fast_answer_file] | path join`
  --bison(-B)  #use google bison instead of gemini
  --chat(-c)   #use chat mode (text only).
  --database(-D) #load chat conversation from database
  --web_search(-w) #include web search results into the prompt
  --web_results(-W):int = 2 #how many web results to include
] {
  let fast_prompt = [$env.AI_TOOLS.ai_database_path $env.AI_TOOLS.fast_prompt_file] | path join
  let fast_answer = [$env.AI_TOOLS.ai_database_path $env.AI_TOOLS.fast_answer_file] | path join

  #check input
  let prompt = (
    if not $fast {
      if ($prompt | is-empty) {$in} else {$prompt}
    } else {
      open $fast_prompt
    }
  )
  
  if $vision and ($image | is-empty) {
    return-error "vision models need and image file!"
  }
    
  let temp = (
    if ($temperature | is-empty) {
      match $programmer {
        true => 0.7,
        false => 0.9
      }
   } else {
    $temperature
   }
  )

  let system = (
    if ($system | is-empty) {
      if $list_system {
        ""
      } else if $programmer {
        "programmer"
      } else {
        "assistant"
      }
    } else {
      $system
    }
  )

  #chat mode
  if $chat {
    google_ai $prompt -c -D $database -t $temp --select_system $system -p $list_preprompt  -l $list_system -d $delimit_with_quotes -w $web_search -W $web_results
    return
  }

  #single question mode
  let answer = (
    if $vision {
      google_ai $prompt -t $temp -l $list_system -m gemini-pro-vision -p $list_preprompt -d true -i $image
    } else {
      match $bison {
        true => {google_ai $prompt -t $temp -l $list_system -p $list_preprompt -m text-bison-001 -d true -w $web_search -W $web_results},
        false => {google_ai $prompt -t $temp -l $list_system -p $list_preprompt -d true -w $web_search -W $web_results},
      }
    }
  )

  if $fast {
    $answer | save -f $fast_answer
    return
  } else {
    return $answer  
  } 
}

#alias for bard
export alias bard = askai -c

#summarize the output of google_search via ai
export def google_search-summary [
  question:string     #the question made to google
  web_content?: table #table output of google_search
  --md(-m)            #return concatenated md instead of table
] {
  let max_words = 18000
  let web_content = if ($web_content | is-empty) {$in} else {$web_content}
  let n_webs = $web_content | length

  let model = "gemini"
  let prompt = (
    open ([$env.AI_TOOLS.config_path $env.AI_TOOLS.preprompt_file] | path join) 
    | get summarize_html2text 
    | str replace "<question>" $question 
  )

  print (echo-g $"asking ($model) to summarize the web results...")
  mut content = []
  for i in 0..($n_webs - 1) {
    let web = $web_content | get $i

    print (echo-c $"summarizing the results of ($web.displayLink)..." "green")

    let truncated_content = $web.content | ^awk ("'BEGIN{total=0} {total+=NF; if(total<=(" + $"($max_words)" + ")) print; else exit}'")

    let complete_prompt = $prompt + "\n'''\n" + $truncated_content + "\n'''"

    let summarized_content = google_ai $complete_prompt --select_system html2text_summarizer

    $content = $content ++ $summarized_content
  }

  let content = $content | wrap content
  let updated_content = $web_content | reject content | append-table $content

  if $md {
    mut md_output = ""

    for i in 0..($n_webs - 1) {
      let web = $updated_content | get $i
      
      $md_output = $md_output + "# " + $web.title + "\n"
      $md_output = $md_output + "link: " + $web.link + "\n\n"
      $md_output = $md_output + $web.content + "\n\n"
    }

    return $md_output
  } else {
    return $updated_content
  }
} 

## other tools

#google search
export def google_search [
  ...query:string
  --number_of_results(-n):int = 5 #number of results to use
  --verbose(-v) #show some debug messages
  --md(-m) #md output instead of table
] {
  let query = if ($query | is-empty) {$in} else {$query} | str join " "

  if ($query | is-empty) {
    return-error "empty query!"
  }

  let apikey = $env.AI_TOOLS.api_keys.google.search
  let cx = $env.AI_TOOLS.api_keys.google.search_cx

  if $verbose {print (echo-g $"querying to google search...")}
  let search_result = {
      scheme: "https",
      host: "www.googleapis.com",
      path: "/customsearch/v1",
      params: {
          key: $apikey,
          cx: $cx
          q: ($query | url encode)
      }
    } 
    | url join
    | http get $in 
    | get items 
    | first $number_of_results 
    | select title link displayLink

  let n_result = $search_result | length

  mut content = []

  for i in 0..($n_result - 1) {
    let web = $search_result | get $i
    if $verbose {print (echo-c $"retrieving data from: ($web.displayLink)" "green")}
      
    let raw_content = try {http get $web.link} catch {""}

    let processed_content = (
      try {
        $raw_content
        | html2text --ignore-links --ignore-images --dash-unordered-list 
        | lines 
        | uniq
        | to text
      } catch {
        $raw_content
      }
    )

    $content = $content ++ $processed_content
  }

  let final_content = $content | wrap "content"
  let results = $search_result | append-table $final_content

  if $md {
      mut md_output = ""

      for i in 0..(($results | length) - 1) {
        let web = $results | get $i
        
        $md_output = $md_output + "# " + $web.title + "\n"
        $md_output = $md_output + "link: " + $web.link + "\n\n"
        $md_output = $md_output + $web.content + "\n\n"
      }

      return $md_output
  } 

  return $results
}

#create joplin note
export def "joplin create" [ 
  title:string            #title of the note
  content?:string         #body of the note (can be piped)
  --tags(-t):string       #comma separated list of tags
  --notebook(-n):string   #specify notebook instead of list
] {
  let content = if ($content | is-empty) {$in} else {$content}

  let notebooks = joplin ls / | lines | str trim 
  let notebook = (
    if ($notebook | is-empty) {
      $notebooks
      | input list -f (echo-g "select notebook for the note: ")
    } else {
      $notebook
    }
  )

  if $notebook not-in $notebooks {
    return-error "notebook doesn't exists!"
  }
  
  joplin use $notebook
  joplin mknote $title

  if not ($tags | is-empty) {
    $tags
    | split row ","
    | each {|tag|
        joplin tag add $tag $title
        sleep 0.1sec
      }    
  }

  joplin set $title body $"'($content)'"
  joplin sync
} 

#green echo
export def echo-g [string:string] {
  echo $"(ansi -e { fg: '#00ff00' attr: b })($string)(ansi reset)"
}

#red echo
export def echo-r [string:string] {
  echo $"(ansi -e { fg: '#ff0000' attr: b })($string)(ansi reset)"
}

#custom color echo
export def echo-c [string:string,color:string,--bold(-b)] {
  if $bold {
    echo $"(ansi -e { fg: ($color) attr: b })($string)(ansi reset)"
  } else {
    echo $"(ansi -e { fg: ($color)})($string)(ansi reset)"
  }
}

#generate error output
export def return-error [msg] {
  error make -u {msg: $"(echo-r $msg)"}
}

#append table to table
export def append-table [tab2:table,tab1?:table] {
  let tab1 = if ($tab1 | is-empty) {$in} else {$tab1}

  if ($tab1 | length) != ($tab2 | length) {
    return-error "tables must have the same length!"
  }

  $tab1
  | dfr into-df 
  | dfr append ($tab2 | dfr into-df) 
  | dfr into-nu
}
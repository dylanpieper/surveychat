# surveychat <a href="https://dylanpieper.github.io/surveychat/"><img src="man/figures/logo.png" align="right" height="139" alt="A round stone tablet with carved lips in the center, surrounded by carved checkboxes and radio buttons."/></a>

surveychat is a [shinychat](https://posit-dev.github.io/shinychat/) toolkit for conversational and adaptive surveys. Participants answer in natural dialogue with a chat interface. An LLM routed through [ellmer](https://ellmer.tidyverse.org/) validates typed answers, extracts data, and writes adaptive questions or skips ones already answered. Each answer goes to SQL tables through a [DBI](https://dbi.r-dbi.org/) connection. Earlier answers pipe into later questions, so participants get treated in context and you get richer data.

## Installation

``` r
pak::pak("dylanpieper/surveychat")
```

## Example

A workshop sign-up that starts in the AI chat, with buttons to change to the form or to both side by side, which is useful while you test a survey. Choose the model with `chat`, as `"provider/model"`; the provider reads its own key, such as `ANTHROPIC_API_KEY`, and the model must support structured output.

``` r
surveychat::run_example("panel-chat-form", chat = "anthropic/claude-haiku-4-5")
```

<p align="center">
<img src="man/figures/panel-chat-form.gif" alt="Screen recording of the AI Coding Workshop sign-up in the AI chat. The user types the name Dylan, and the chat replies Hey, Dylan! and asks for a role. Dylan clicks Software Engineer, checks two workshop days, clicks Maybe for dinner, and types Vegetarian for diet and Agentic coding as a learning goal. The chat then writes a new question about experience with AI tools. Dylan types I use Claude Code, and the chat replies: Great! You're already familiar with Claude. Let's build on that today. It asks about a project, Dylan names an R package called surveychat, and the chat asks what surveychat does. After that answer, the chat comments in one sentence, says Thanks, Dylan! See you at the workshop., and shows Survey complete."/>
</p>

## Learn more

-   [Design a survey](https://dylanpieper.github.io/surveychat/articles/design-surveys.html): build and run a survey
-   [Survey data](https://dylanpieper.github.io/surveychat/articles/survey-data.html): tables, data dictionary, and supported databases
-   [A chat in a sidebar](https://dylanpieper.github.io/surveychat/articles/chat-sidebar.html): ice cream shop example, with a drawer for the answers

## Python port note

surveychat will be ported to Python to align with the R and Python codebase for shinychat.

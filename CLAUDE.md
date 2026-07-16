## Project "Поток"
App that works with notes: 
- recording voice, ai recognition 
- input text and pictures
- notes have tags
- notes in a folder (logically - name of project) 

## Communicate style
- Write only what is important
- don't write emotions
- Talk less - say more

## Agents

Use agents if needed. Your area of ​​responsibility is to analyze the tasks and give clear instructions to the agents (which file to look at, maybe which lines) **write only the necessary, relevant context to agents**. **You receive the work results and provide me a brief, factual report.**

### Agent run rules

**Run agent if task**
- **Is complex and you can decompose task into subtasks**
- is one-step and you can get only result from agent to keep context not oveflowed
- Requires extensive codebase search (more than 3 grep/glob queries)
- Independent of the current context and can be executed in parallel
- Requires protecting the main context from large volumes of results (e.g., reading many files)
- Is an open-ended search ("find all places where...", "check all files for...")

**Dont run if**
- You already know a specific file or symbol—use `Read`/`Grep` directly.
- The agent duplicates the work you've already done.

### Model for agent
| Difficulty | Model | When use |
|---|---|---|
| **Easy** | `"sonnet 5"` | File search, codebase grep, reading and summarizing, minor edits |
| **Medium** | `"sonnet 5"` | Refactoring, test writing, architecture analysis, easy bug fix |
| **Hard** | `"Fable"` | Designing new feature, deep code review, cross-module changes |

## SKILLS (you, agents)
**use the following skills if task is complex**
- `senior-dev` - for every programming tasks
- `review-skills` - for deep review

## Design
- Modern design
- Customizable theme

## Tests
Write tests if needed in folder /tests

## Context
AI CLAUDE write in files /docs. Good code, patterns, atomic, async - yes, bugs - no
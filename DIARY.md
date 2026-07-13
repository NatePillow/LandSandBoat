# Preamble

This project is part of a series to use AI tools under various different scenarios.

* Standard scenario:
    * **This project**
    * Domain knowledge, planning, and core development was completed by the dev, an AI tool was then "onboarded" onto the project while it was being prepped for long-term feature development, and then said feature development is turned over to the AI tool indefinitely.
* Full scenario:
    * [fowl-jungle-editor](https://github.com/NatePillow/fowl-jungle-editor)
    * Zero human code, only human design, guidance, and correction.
* Legacy scenario:
    * [fowl-jungle-public](https://github.com/NatePillow/fowl-jungle-public)
    * A well-established codebase with particular quirks that give AI tools a hard time. This has forced a decision to refactor code to try to better equip AI tools for success.

---

# Project Diary

This project has progressed through four phases and is now in alpha. The project goals included:

* Exposure and familiarity with C++
* Exposure and familiarity with a scripting language, in this case Lua
* Using AI tools in a new scenario

---

### Phase 1: PoC, domain knowledge, and tooling research

* Gaining knowledge of the backend C++/Lua codebase and it's mariadb schema.
* Gaining knowledge of the frontend client and it's Lua scripting framework.
* Iterating through several proof of concepts, each one expanding the scope closer to the envisioned outcome.
* Bootstrapping the project with core capabilities to make it usable, testable, and stable.
* Stabilizing deployment and processes.
* Evaluated several AI tools against professional experience with Kiro as the baseline and ultimately selected Claude:
  * Gemini CLI: Often can be just as impressive and the UI was an improvement over Kiro, however it also seemed to have more trust-breaking events.
  * Claude CLI: Kiro with a different wrapper and superior UI.
  * Ollama + Qwen/Deepseek + Aider: Locally running open-weight models that were very clearly inferior to non-local offerings. Walked away with the impression that these models are not only behind frontier models by 12 months or so as is sometimes claimed. The gap seemed much more substantial than that. Aider as a UI was passable although bare. Ollama stands out as the one bright spot in this workflow, as using it to bootstrap local models was very straightforward.
* Used Gemini and Claude to solve a couple non-trivial problems.

---

### Phase 2: Refactoring the core and onboarding Claude

* Pair programming with Claude to refactor the core of the project.
* The dev focused on the design and overall organization, often queueing up several prompts at a time.
* Identified and addressed the areas where Claude was consistently tripping up.
* Started delegating bug fixes to Claude with increasingly distant oversight.
* Created the first completely AI generated class to power Claude's first feature.

---

### Phase 3: Don't ask me Claude, you're the one that built it

* The dev doesn't write code anymore, instead directing his efforts towards design, efficiency, UX, and product ideation. Claude implements all new features and bug fixes.
* Addon files that contain only AI generated code have the dragon header, and it should be assumed the rest contain a mixture of human and AI generated code.
* Claude has proven competent at the first pass of UI design and can handle backend work, but struggles to identify the second and third cycle activities.
* Claude will design itself into a very ugly corner if you let it and will not hesitate to generate duplicate code.
* Development cycle is: 
  * Ideation and prompting, directing Claude into a sustainable design and then leaving mechanics to the machine
  * Deployment and testing
  * Feeding bug reports back into Claude, and providing guidance during root cause analysis when needed
* Claude consumer-tier problems:
  * I couldn't imagine building an agent or doing spec-driven development with this plan
  * The context window is way too small
  * Compaction can be brutal, it happens more frequently and is a clear pain point
  * Cascading failures are more prevalent
  * There can be long queue times before processing starts
  * Extra usage burns money very quickly, not at all worth it
  * How much longer is the $20 plan going to exist? How much longer can I stand to use it?
* We need to set these tools up for success
  * The limitations of the cheapest consumer plan amplifies many of the problems with these tools to engineer around and helps to make them far more visible.
  * E.g. By including ADKv3 interface documentation directly within the repo used to develop addons:
    * Claude hallucinations in this area pretty much ceased
    * Confusion about the ADK version still rarely appeared even with steering files, but with documentation stored locally it becomes cheap and easy to prompt Claude to verify after long iterative sessions

---

### Phase 4: Actually, let me write some of it

* Core files and functionality have seen increasingly large numbers of human edits and interventions.
* Refactoring AI code has become commonplace, although velocity is still elevated. There is clear value, although the analysis becomes muddier and muddier over time.

---

# Is this an infohazard?

The project goals lead to large amounts of automation, both inside and outside of combat. Arguments are below for different client addon release strategies.

* DLL
    * Porting to C++ and building a dll before releasing.
    * There is a high volume of logic and ideas present, and we shouldn't give malicious actors a head start even if it is incomplete. While many capabilities rely on custom packets not available elsewhere, a non-trivial proportion of capabilities will function using retail packets.
* Lua
    * Release in their base lua form with no obfuscation in a show-don't-tell approach.
    * The hard part for any malicious actor is going to be evading detection, and there is nothing like that in any addons or planned. In fact, they are very noisy and will probably get detected very quickly.
    * 0x150 protects innocent users who turn these on somehow while pointing at retail. Until the server ident packet is received, the addons are inert.
* Server-side automation
    * Just port all meaningful functionality to the backend, make the client addons more like wrappers, and avoid the problem entirely.  

Conclusion: Server-side AI (completed)


  Part 1: The Overall Project and Its Objectives

  1.1. The Core Mission: From Linear Pipeline to Strategic 
  Executor

  The fundamental goal of this project is to transform the
  research engine from a brittle, strategically naive pipeline
  into a resilient, adaptive, and intelligent executor.

   * Evidence (`brd_v1.md`, `thinking-stream.md`): The project was
     initiated to solve the "Tokyo venue" problem, where an early,
     flawed search query (web_search) would cause the entire run to
     fail because the system had no "Plan B." It executed a simple,
     pre-defined list of tasks in a linear fashion.
   * Objective: The system must be able to execute a complex,
     agent-driven strategy that can react to failure. It needs to
     move beyond a simple task queue and become a true executor of
     a strategic plan.

  1.2. The North Star Architecture: A Graph-Based, Domain-Driven 
  System

  To achieve this mission, a specific "North Star" architecture
  was designed, grounded in Domain-Driven Design (DDD).

   * Evidence (`north_star_data_flow.md`): The architecture
     explicitly defines two primary Bounded Contexts:
       1. The `Planning` Context: Responsible for generating a
          strategic plan. Its key output is an ExecutablePlan.
       2. The `Execution` Context: Responsible for taking that
          ExecutablePlan and driving it to completion.
   * Objective R2 (Graph-Based Planning): The ExecutablePlan must
     be a directed acyclic graph.
       * Evidence (`task.py` schema, `north_star_data_flow.md`): The
          Task schema was updated to include depends_on and
         alternative_to fields. This is the "language" of the graph,
          allowing the Planning context to express complex
         relationships like dependencies ("Task C cannot start until
          A and B are complete") and contingencies ("If Task D
         fails, execute Task D-Alternative").
   * Objective R5 (Architectural Clarity): The components must have
     clear, non-overlapping responsibilities.
       * Evidence (`north_star_data_flow.md`): The document defines
         the roles precisely: PlanFormulationService owns planning
         strategy. WorkflowOrchestrator owns execution. LiveRun is
         the Aggregate Root that owns the state of the run.
         AgentService is intended to be a low-level infrastructure
         client for LLM calls.

  1.3. The "Deep Think" Methodology

  To ensure the generated plans are strategically sound, the
  project specified a multi-agent planning process.

   * Evidence (`The Iterated Implementation Plan (v3).md`): The
     plan details a three-stage process: Primary Planner -> Red 
     Team Critic -> Final Planner. This collaborative process is
     designed to produce a vetted, resilient ExecutablePlan that
     contains the crucial depends_on and alternative_to
     relationships.
   * Objective R1 (Agent-Driven Strategy): This methodology fulfills
      the requirement that the strategic intelligence comes from the
      agents, not from hard-coded Python logic.

  In summary, the overall project objective is to build a system
  where a sophisticated, multi-agent Planning service generates a
  graph-based ExecutablePlan, which is then passed to a
  graph-aware Execution service that can intelligently navigate
  its dependencies and contingencies.

  ---

  Part 2: Detailed Breakdown of the Current Problem

  The current problem is a failed integration between the
  Planning and Execution contexts, caused by an incomplete
  refactoring effort. The system is in a "half-state" where the
  new execution engine is in place, but the new planning engine
  is not yet connected to it.

  2.1. The "Architectural Schism": Two Competing Planners

  The codebase currently contains two mutually exclusive planning
  pathways.

   * Path A (Legacy V1): The `agent_service.run_planner` method.
       * Evidence (`agent_service.py`): This method exists and
         contains the logic for a single-shot call to the
         research_planner agent.
       * Evidence (`2_research_plan.json` artifact): This method is
         proven to produce a flat, linear list of tasks with no
         graph relationships.

   * Path B (North Star V2): The `PlanFormulationService`.
       * Evidence (`plan_formulation_service.py`): This service
         exists and correctly implements the multi-agent "Deep
         Think" orchestration (draft_plan -> critiques -> 
         synthesize_plan).
       * Evidence (`agent_service.py`): The low-level agent clients
         required by this service (run_primary_planner, run_critic,
         run_final_planner) also exist.

  2.2. The Point of Failure: The `entrypoint`

  The system's main entrypoint is still wired to the legacy V1 path.


   * Evidence (`entrypoint.py`): The code at line 241 explicitly
     calls await agent_service.run_planner(planner_context).
   * Fact: There is no code path in the entrypoint that
     instantiates or calls the PlanFormulationService.

  2.3. The Observable Symptoms

  This failed integration manifests in two ways:

   1. Symptom 1: No Graph Behavior.
       * Description: The system appears to ignore all the new
         graph logic.
       * Causal Chain: entrypoint calls agent_service.run_planner ->
          a flat plan is generated -> the Orchestrator receives this
          flat plan -> the PlanExecutionGraph is created but, when
         queried, correctly reports that all tasks are "ready"
         because there are no dependencies -> the Orchestrator
         executes them as a simple list. The new system is working
         perfectly, but it is being fed a plan that does not utilize
          its features.

   2. Symptom 2: Pydantic `ValidationError`s.
       * Description: The run fails with errors like
         originating_task_id ... Input should be a valid string.
       * Causal Chain: This is a secondary effect of the
         architectural schism. While the entrypoint is still on the
         V1 planning path, other parts of the codebase, like the
         RichResult schema, have been updated to V2 standards. The
         V1 planner generates tasks that are missing fields now
         required by the V2 schemas, causing validation to fail
         downstream. This proves that the system is i
------

  Here is the iterated implementation plan for Sub-Epic 3.3: Core Orchestration Logic.

  ---

  Iterated Implementation Plan (v4): Core Orchestration Logic

  Objective: To transform the WorkflowOrchestrator from a simple queue processor into a true graph
  executor. The orchestrator will now delegate all strategic "what to do next" decisions to the
  PlanExecutionGraph and will be responsible for driving the state transitions of that graph.

  Prerequisites:
   * The PlanExecutionGraph class is implemented and unit-tested.
   * The LiveRun class has the set_executable_plan method and the necessary graph state attributes.
   * The resource-aware concurrency model (O1) is implemented and verified.

  ---

  Node `O2a_ROOT_DISPATCH`: Initial Task Population

  Goal: Modify the orchestrator's startup logic. Instead of assuming tasks are already on the queue, the
  orchestrator must now actively query the graph for the initial set of runnable tasks and enqueue them
  itself.

  Detailed Implementation Steps:

   1. Instantiate the Graph: In the WorkflowOrchestrator.execute method, after the settings have been
      loaded, the first action will be to instantiate the PlanExecutionGraph.
       * Code: graph = PlanExecutionGraph(executable_plan, self.run_actor.run_id)
       * Note: This assumes the executable_plan (list[Task]) is passed into the execute method. This will be
          the responsibility of the RunLifecycleManager as part of INT_1. For now, our tests will provide a
         fixture for this plan.

   2. Query for Initial Tasks: Immediately after instantiation, call the graph's get_ready_tasks() method.
      This will return a list of "root" tasks (those with no dependencies).
       * Code: initial_tasks = graph.get_ready_tasks()

   3. Propose Initial Tasks: Iterate through the initial_tasks list. For each Task object returned by the
      graph, create a ReflectionTaskInfo object and propose it to the LiveRun's task queue.
       * Code:

    1         for task in initial_tasks:
    2             # Mark the task as "running" in the graph *before* enqueuing
    3             # to prevent it from being selected again.
    4             graph.record_task_running(task.task_id)
    5 
    6             rti = ReflectionTaskInfo(
    7                 task_id=task.task_id,
    8                 priority=task.priority,
    9                 task_type=task.task_type,
   10                 params=task.params,
   11                 description=task.description,
   12                 origin_agent="Planner", # Or a more appropriate origin
   13                 origin_requirement_id=task.originating_task_id
   14             )
   15             await self.run_actor.propose_task(rti)
       * Critical Detail: We must call graph.record_task_running(task.task_id) before proposing the task.
         This is crucial to prevent race conditions. It immediately updates the graph's internal state,
         ensuring that a subsequent, rapid call to get_ready_tasks() would not return the same task again.

  ---

  Node `O2c_STATE_UPDATE_INTEGRATION`: Reporting Task Outcomes

  Goal: Modify the _run_task_worker to report the success or failure of every task back to the
  PlanExecutionGraph. This is the feedback loop that drives the graph's state transitions.

  Detailed Implementation Steps:

   1. Pass the Graph to the Worker: The PlanExecutionGraph instance must be available within the
      _run_task_worker. The cleanest way to achieve this is to pass it from the _producer when the worker
      task is created.
       * `_producer` Change: tg.create_task(self._run_task_worker(task_dict, semaphore, graph))
       * `_run_task_worker` Signature Change: async def _run_task_worker(self, task_dict: dict, semaphore: 
         asyncio.Semaphore, graph: PlanExecutionGraph) -> None:

   2. Report Success: Inside the try block of _run_task_worker, after a successful execution (i.e., after
      _process_rich_result is called and no exception was raised), add a call to the graph.
       * Code: graph.record_task_success(task.task_id)

   3. Report Failure: Inside the except Exception block, this is where we will report the failure.
       * Code: graph.record_task_failure(task.task_id)
       * Note: We will need to define the different failure types in O2b before this can be fully
         implemented, but the basic call will be here.

  ---

  Node `O2d_ENQUEUE_NEXT_TASKS`: Unlocking Dependent Tasks

  Goal: After reporting a task's outcome to the graph, the orchestrator must immediately ask the graph
  which new tasks, if any, are now ready to run. These new tasks must then be enqueued.

  Detailed Implementation Steps:

   1. Create a Helper Method: To avoid code duplication, create a new private method: async def 
      _enqueue_ready_tasks(self, graph: PlanExecutionGraph) -> None:. This method will contain the logic for
      getting and proposing newly unlocked tasks.

   2. Implement the Helper Logic:
       * Code:

    1         async def _enqueue_ready_tasks(self, graph: PlanExecutionGraph) -> None:
    2             newly_ready_tasks = graph.get_ready_tasks()
    3             if not newly_ready_tasks:
    4                 return
    5 
    6             log.info("Graph has unlocked new tasks.", count=len(newly_ready_tasks))
    7             for task in newly_ready_tasks:
    8                 graph.record_task_running(task.task_id) # Mark as running immediately
    9                 rti = ReflectionTaskInfo(...) # Create RTI as before
   10                 await self.run_actor.propose_task(rti)

   3. Integrate the Helper Call: Call this new _enqueue_ready_tasks(graph) method from within
      _run_task_worker in two places:
       * Immediately after graph.record_task_success(task.task_id).
       * Immediately after graph.record_task_failure(task.task_id).

  This ensures that after any state change in the graph, we immediately check for and enqueue any newly
  available work.

  This detailed plan provides a clear, step-by-step guide for transforming the orchestrator. It respects
  our architectural principles by keeping state logic within the graph and treating the orchestrator as
  the driver.
---
Status Report: Graph-Based Orchestrator Refactor

  1. Overall Progress: Where We Are

  We have successfully completed a major phase of the refactor. The foundational work is done, and the
  first part of the WorkflowOrchestrator upgrade is now complete and verified.

  Here is the updated status of the project dependency graph:

   * EPIC 1: The Data Contract: ✅ DONE
   * EPIC 2: Deep Think Methodology Implementation: ✅ DONE
   * EPIC 3: Orchestrator Upgrade (The Executor):
       * Sub-Epic 3.1: Foundational State Management (`O0`): ✅ DONE
       * Sub-Epic 3.2: Resource-Aware Concurrency (`O1`): ✅ JUST COMPLETED


  ┌─────────────┬──────────────────────────────┬────┬──────────────────────────────────────────────┐
  │ Node        │ Description                  │ St │ Evidence of Verification                     │
  ├─────────────┼──────────────────────────────┼────┼──────────────────────────────────────────────┤
  │ `O1a_SET... │ Update ToolSettings for p... │ ✅  │ The config.py and settings...yaml files h... │
  │ `O1b_MUL... │ Modify orchestrator to ma... │ ✅  │ The WorkflowOrchestrator now initializes ... │
  │ `O1c_ACQ... │ Modify worker to use the ... │ ✅  │ The _run_task_worker method now correctly a... │
  └─────────────┴──────────────────────────────┴────┴──────────────────────────────────────────────┘


  2. Verification Status: How We Know It Works

  All completed work is backed by a suite of targeted tests that verify the correctness of each component
  in isolation.

   * The Data Contract (`S1`, `S2`) is verified by test_task_schema.py.
   * The `PlanFormulationService` (`DTM_1-5`) is verified by test_plan_formulation_service.py.
   * The `LiveRun` Graph Logic (`O0a-d`) is verified by test_execution_graph.py.
   * The Resource-Aware Concurrency (`O1a-c`) is now verified by the new `test_concurrency_limits.py` test 
     file. This test successfully proved that the orchestrator correctly limits concurrent tasks based on
     their specific resource type (browser, default, etc.), confirming the implementation is working as
     designed.

  3. Remaining Work: What Is Next

  The next major body of work is to implement the core graph-execution logic within the orchestrator. The
  following nodes are ⚫️ NOT STARTED:

   * Sub-Epic 3.3: Core Orchestration Logic
       * O2a_ROOT_DISPATCH: Modify the orchestrator's startup logic to get the initial ready tasks from the
         PlanExecutionGraph.
       * O2b_FAILURE_TYPES: Define and classify the different types of task failures (Hard vs. Logical).
       * O2c_STATE_UPDATE_INTEGRATION: Modify _process_rich_result to call the new state transition methods
         on the PlanExecutionGraph (record_task_success, record_task_failure).
       * O2d_ENQUEUE_NEXT_TASKS: Implement the logic to take the newly ready tasks (returned by the graph)
         and propose them to the LiveRun's priority queue.

   * Sub-Epic 3.4: Verification
       * O3a_GRAPH_ORCHESTRATION_TEST: Create the new, high-level integration test file
         (test_graph_orchestration.py) to verify the behavior of the fully refactored orchestrator.

   * EPIC 4: Integration & Polish
       * INT_1_CONNECT_DTM_TO_ORCHESTRATOR
       * V1_CONSTRAINT_VALIDATOR
       * V2_INTEGRATE_VALIDATOR
       * E1_SEMANTIC_EVENTS

  Summary:
  The implementation is on solid ground. The next step is to begin Sub-Epic 3.3, starting with node
  O2a_ROOT_DISPATCH.Understood. I will now proceed with the next phase of the refactor: Sub-Epic 3.3: 
  Core Orchestration Logic, starting with node O2a_ROOT_DISPATCH.

  Goal for `O2a_ROOT_DISPATCH`: Modify the orchestrator's startup logic to get the initial ready tasks
  from the PlanExecutionGraph and enqueue them, rather than assuming the queue is already populated.

  To do this correctly, I first need to re-verify the final architecture of the PlanExecution
---
Status Report: Graph-Based Orchestrator Refactor

  1. Overall Progress: Where We Are

  We have successfully completed a major phase of the refactor. The foundational work is done, and the
  first part of the WorkflowOrchestrator upgrade is now complete and verified.

  Here is the updated status of the project dependency graph:

   * EPIC 1: The Data Contract: ✅ DONE
   * EPIC 2: Deep Think Methodology Implementation: ✅ DONE
   * EPIC 3: Orchestrator Upgrade (The Executor):
       * Sub-Epic 3.1: Foundational State Management (`O0`): ✅ DONE
       * Sub-Epic 3.2: Resource-Aware Concurrency (`O1`): ✅ JUST COMPLETED


  ┌─────────────┬──────────────────────────────┬────┬──────────────────────────────────────────────┐
  │ Node        │ Description                  │ St │ Evidence of Verification                     │
  ├─────────────┼──────────────────────────────┼────┼──────────────────────────────────────────────┤
  │ `O1a_SET... │ Update ToolSettings for p... │ ✅  │ The config.py and settings...yaml files h... │
  │ `O1b_MUL... │ Modify orchestrator to ma... │ ✅  │ The WorkflowOrchestrator now initializes ... │
  │ `O1c_ACQ... │ Modify worker to use the ... │ ✅  │ The _run_task_worker method now correctly a... │
  └─────────────┴──────────────────────────────┴────┴──────────────────────────────────────────────┘


  2. Verification Status: How We Know It Works

  All completed work is backed by a suite of targeted tests that verify the correctness of each component
  in isolation.

   * The Data Contract (`S1`, `S2`) is verified by test_task_schema.py.
   * The `PlanFormulationService` (`DTM_1-5`) is verified by test_plan_formulation_service.py.
   * The `LiveRun` Graph Logic (`O0a-d`) is verified by test_execution_graph.py.
   * The Resource-Aware Concurrency (`O1a-c`) is now verified by the new `test_concurrency_limits.py` test 
     file. This test successfully proved that the orchestrator correctly limits concurrent tasks based on
     their specific resource type (browser, default, etc.), confirming the implementation is working as
     designed.

  3. Remaining Work: What Is Next

  The next major body of work is to implement the core graph-execution logic within the orchestrator. The
  following nodes are ⚫️ NOT STARTED:

   * Sub-Epic 3.3: Core Orchestration Logic
       * O2a_ROOT_DISPATCH: Modify the orchestrator's startup logic to get the initial ready tasks from the
         PlanExecutionGraph.
       * O2b_FAILURE_TYPES: Define and classify the different types of task failures (Hard vs. Logical).
       * O2c_STATE_UPDATE_INTEGRATION: Modify _process_rich_result to call the new state transition methods
         on the PlanExecutionGraph (record_task_success, record_task_failure).
       * O2d_ENQUEUE_NEXT_TASKS: Implement the logic to take the newly ready tasks (returned by the graph)
         and propose them to the LiveRun's priority queue.

   * Sub-Epic 3.4: Verification
       * O3a_GRAPH_ORCHESTRATION_TEST: Create the new, high-level integration test file
         (test_graph_orchestration.py) to verify the behavior of the fully refactored orchestrator.

   * EPIC 4: Integration & Polish
       * INT_1_CONNECT_DTM_TO_ORCHESTRATOR
       * V1_CONSTRAINT_VALIDATOR
       * V2_INTEGRATE_VALIDATOR
       * E1_SEMANTIC_EVENTS

  Summary:
  The implementation is on solid ground. The next step is to begin Sub-Epic 3.3, starting with node
  O2a_ROOT_DISPATCH.

----
 The Project Dependency Graph - Current Status

  Status Key:
   * ✅ DONE: The work for this node is complete and committed.
   * 🟡 IN PROGRESS: The work for this node has been started.
   * ⚫️ NOT STARTED: The work for this node has not yet begun.

  ---

  EPIC 1: The Data Contract (The Blueprint)
  Goal: Formally define the language of our strategic plans.

   * Node `S1_SCHEMA_UPDATE`
       * Status: ✅ DONE
       * Evidence: The Task schema in push_search/schemas/task.py has been updated and committed.

   * Node `S2_CONTRACT_TEST`
       * Status: ✅ DONE
       * Evidence: The sample_graph_plan.json fixture and test_task_schema.py have been created and committed.

  ---

  EPIC 2: Deep Think Methodology Implementation
  Goal: Build the "brain" that generates the strategic plan.

   * Node `DTM_1_SCHEMAS`
       * Status: ✅ DONE
       * Evidence: The deepthink_schema.py file with the Critique and PlanningBundle models has been created and committed.

   * Node `DTM_2_PROMPTS`
       * Status: ✅ DONE
       * Evidence: The three prompt files for the Deep Think agents have been created and committed.

   * Node `DTM_3_SERVICE_SCAFFOLD` & `DTM_4_SERVICE_LOGIC`
       * Status: ✅ DONE
       * Evidence: The deepthink_planners.py and plan_formulation_service.py files have been implemented and committed.

   * Node `DTM_5_DTM_VALIDATION_TEST`
       * Status: ✅ DONE
       * Evidence: The test_plan_formulation_service.py file, which validates the service's orchestration logic, has been created, run successfully, and committed.

  ---

  EPIC 3: Orchestrator Upgrade (The Executor)
  Goal: Upgrade the `WorkflowOrchestrator` to execute the agent's strategic plan.

   * Node `O0a_LIVERUN_STATE`
       * Status: ✅ DONE
       * Evidence: The new graph state attributes have been added to LiveRun and committed.

   * Node `O0b_LIVERUN_PARSING`
       * Status: ✅ DONE
       * Evidence: The set_executable_plan method has been implemented in LiveRun and committed.

   * Node `O0c_LIVERUN_API`
       * Status: ✅ DONE
       * Evidence: The new state transition and query API (get_ready_tasks, record_task_*) has been implemented in LiveRun as part of the PlanExecutionGraph logic.

   * Node `O0d_LIVERUN_TESTS`
       * Status: ✅ DONE
       * Evidence: The test_execution_graph.py file, which validates the new LiveRun graph logic (via the PlanExecutionGraph class), has been created, run successfully,
         and committed.

   * All other nodes in EPIC 3 and EPIC 4 are `⚫️ NOT STARTED`.

  ---

  Summary of Progress

  We have made significant and verifiable progress.

   * Workstream A (Agent Engineering) is functionally complete and unit-tested.
   * The foundational State Management portion of Workstream B (Systems Engineering) is also complete and unit-tested.

  The next step is to begin the core implementation work for the WorkflowOrchestrator itself, starting with Sub-Epic 3.2: Resource-Aware Concurrency.

╭───────────────────────────────────────────╮
│  > What are the nodes that are not done?  │
╰───────────────────────────────────────────╯

✦ Of course. Here is a clear list of all the nodes in our project plan that are `⚫️ NOT STARTED`.

  ---

  EPIC 3: Orchestrator Upgrade (The Executor)

  This epic is now our primary focus.

  SUB-EPIC 3.2: Resource-Aware Concurrency
   * Node `O1a_SETTINGS_UPDATE`: Update the ToolSettings model to support per-task-type concurrency limits.
   * Node `O1b_MULTI_SEMAPHORE`: Modify the WorkflowOrchestrator to create and manage a dictionary of semaphores based on the new settings.
   * Node `O1c_ACQUIRE_RELEASE_LOGIC`: Modify the _run_task_worker to use the correct semaphore for each task it executes.

  SUB-EPIC 3.3: Core Orchestration Logic
   * Node `O2a_ROOT_DISPATCH`: Modify the orchestrator's startup logic to get the initial ready tasks from the PlanExecutionGraph.
   * Node `O2b_FAILURE_TYPES`: Define and classify the different types of task failures (Hard vs. Logical).
   * Node `O2c_STATE_UPDATE_INTEGRATION`: Modify _process_rich_result to call the new state transition methods on the PlanExecutionGraph (record_task_success,
     record_task_failure).
   * Node `O2d_ENQUEUE_NEXT_TASKS`: Implement the logic to take the newly ready tasks (returned by the graph) and propose them to the LiveRun's priority queue.

  SUB-EPIC 3.4: Verification
   * Node `O3a_GRAPH_ORCHESTRATION_TEST`: Create the new, high-level integration test file (test_graph_orchestration.py) to verify the behavior of the fully refactored
     orchestrator.

  ---

  EPIC 4: Integration & Polish

  This epic is the final phase, to be completed after EPIC 3.

   * Node `INT_1_CONNECT_DTM_TO_ORCHESTRATOR`: The final integration step to connect the output of the PlanFormulationService to the input of the WorkflowOrchestrator.
   * Node `V1_CONSTRAINT_VALIDATOR`: Implement the standalone function for validating findings against GSB constraints.
   * Node `V2_INTEGRATE_VALIDATOR`: Replace the simple "zero findings" failure stub in the orchestrator with the new, intelligent constraint validator.
   * Node `E1_SEMANTIC_EVENTS`: Add the new semantic events for graph execution to provide observability.

  In summary, our next body of work is to implement the Resource-Aware Concurrency and Core Orchestration Logic within the WorkflowOrchestrator, and then to build the
  final integration test to verify it all works together.

╭─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│  > Please exhaustively explain your understanding of what we're working on, what the requirements are, and architectural decisions we've made.  │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

✦ Of course. This is the perfect time for such a review. Before diving into the core of the orchestrator, it's critical to ensure we have a shared, exhaustive
  understanding of the mission, the requirements, and the architectural principles that will guide our implementation.

  Here is my exhaustive understanding of the project as it stands.

  ---

  1. What We Are Working On: The Core Problem

  We are fundamentally transforming the research engine from a brittle, linear pipeline into a resilient, strategic executor.

  The core problem, crystallized by the "Tokyo venue" query, is that our current system is strategically naive. It executes a simple, pre-defined list of tasks. If the
  initial strategy proves flawed (e.g., the first search query yields irrelevant results), the entire run fails. It has no "Plan B."

  Our mission is to build a system that can intelligently recover from strategic failures. We are building an engine that can reason about its own plan, recognize when a
  path is not working, and pivot to a pre-defined alternative, just as a human researcher would.

  2. The Requirements: What "Done" Looks Like

  To solve this problem, we have established a set of core requirements for the new system:

   * R1: Agent-Driven Strategy: The "intelligence" to create a complex, resilient research plan must come from the LLM agents, not from hard-coded, brittle Python logic.
     The system must be general-purpose and not tailored to specific query types like geography.
   * R2: Graph-Based Planning: The research plan must be representable as a directed acyclic graph, capable of modeling not just a sequence of tasks, but also:
       * Dependencies: Task C cannot start until Task A and Task B are complete.
       * Contingencies: If Task A fails, the system should execute Task A-Alternative.
   * R3: Priority-Aware Execution: The system must continue to respect the strategic urgency of tasks. When multiple tasks are logically ready to run, the one with the
     highest priority must be executed first.
   * R4: Resource-Aware Concurrency: The system must understand that different tasks consume different resources. It must be able to apply separate concurrency limits
     (e.g., for network-bound vs. CPU-bound tasks) to maximize efficiency and avoid bottlenecks.
   * R5: Architectural Clarity (MECE): The new components must be designed with clear, non-overlapping responsibilities, adhering to Domain-Driven Design principles to
     ensure the system is maintainable and the workflow directory does not become more "muddy."

  3. The Architectural Decisions We Have Made

  To meet these requirements, we have made a series of critical, interlocking architectural decisions.

  Decision A: The "Deep Think" Methodology for Planning

  Instead of a single agent call, we've designed a collaborative, multi-agent sub-system called the PlanFormulationService. This is our implementation of the `Planning` 
  Bounded Context.
   * What it is: A three-stage process (Primary Planner -> Red Team Critic -> Final Planner) that transforms a user's goal into a robust ExecutablePlan.
   * Why: To mitigate the risk of a single agent producing a naive or flawed "first-thought" plan. This process ensures the final plan is vetted for resilience,
     efficiency, and correctness before execution begins.
   * Status: The components for this (deepthink_schema.py, deepthink_planners.py, plan_formulation_service.py) have been scaffolded, implemented, and unit-tested in
     isolation.

  Decision B: The `Task` v2 Schema as the Graph's "Language"

  We decided that the plan graph would be represented as a list[Task], where the Task schema itself contains the relationship information.
   * What it is: The Task schema now includes the agent-generated task_id, and the optional depends_on and alternative_to fields.
   * Why: This approach is evolutionary, not revolutionary. It allows us to represent a complex graph using a simple, serializable list structure. It also serves as the
     formal, version-controlled "API contract" between the Planning context and the Execution context.
   * Status: The schema has been updated in task.py and a contract test has been written and committed.

  Decision C: The `PlanExecutionGraph` as the "Execution Aggregate"

  We explicitly decided against polluting the LiveRun object with a loose collection of graph-related dictionaries. Instead, we encapsulated all execution state and logic
   into a new, dedicated class.
   * What it is: A stateful class that is initialized with the ExecutablePlan. It is the single source of truth for the state of the graph's execution (e.g., which tasks
     are pending, succeeded, failed). It contains all the logic for determining which tasks are ready to run.
   * Why: This is the cornerstone of our MECE design. It creates a clean, isolated component for the `Execution` Bounded Context. It makes the system easier to test,
     debug, and reason about, and it protects the LiveRun aggregate from becoming a "God Object."
   * Status: The execution_graph.py file has been implemented, unit-tested, and committed.

  Decision D: The `WorkflowOrchestrator` as a "Dumb" Executor

  The role of the WorkflowOrchestrator is being redefined.
   * What it is: It is no longer a simple queue processor. It is a state machine driver. Its job is to:
       1. Interact with the PlanExecutionGraph to get the next ready tasks.
       2. Acquire the correct resource semaphore for each task.
       3. Dispatch the task to a handler.
       4. Report the success or failure of the task back to the PlanExecutionGraph.
       5. Repeat.
   * Why: This makes the orchestrator's logic cleaner and more deterministic. It separates the "what to do" (the graph's responsibility) from the "how to do it" (the
     orchestrator's responsibility).
   * Status: This is the work we are about to begin.

---
The Iterated Implementation Plan (v3)

  This plan reflects our final DDD, IA, and phased approach.

  Final Nomenclature:
   * DraftPlan: The initial v1 plan.
   * Critique: A single piece of feedback.
   * Critiques: The collection of feedback (list[Critique]).
   * PlanningBundle: The aggregate object (DraftPlan + Critiques + GSB) sent to the final planner.
   * ExecutablePlan: The final, validated plan sent to the orchestrator.

  ---

  Phase 1: Establish the Shared Contract & Test Harness

  Goal: Create the non-negotiable, shared "blueprint" and the tools to validate it.

   * Workstream (Systems & Agent Collab):
       1. `S1_SCHEMA_UPDATE`: Modify the Task Pydantic schema in push_search/schemas/task.py to include task_id, alternative_to, and depends_on.
       2. `S2_CONTRACT_TEST`: Create the sample_executable_plan.json fixture and a unit test that proves it can be parsed into list[Task].

   * Verifiable Outcome: A merged pull request containing the updated schema and a passing contract test. This formally kicks off the parallel
     workstreams.

  ---

  Phase 2: Parallel Development - The Strategist & The Executor

  Goal: Develop the core components in isolation. The Agent Engineering team will build the PlanFormulationService. The Systems Engineering team will
  build the WorkflowOrchestrator's execution logic.

   * Workstream A (Agent Engineering - Building the `PlanFormulationService`):
       1. `DTM_1_SCHEMAS`: Create the Pydantic schemas for Critique and PlanningBundle.
       2. `DTM_2_PROMPTS`: Create the three new prompts:
           * primary_planner_prompt.txt: To generate the DraftPlan.
           * critic_agents_prompt.txt: A unified prompt for all critics, explaining how to analyze a DraftPlan and produce a Critique.
           * final_planner_prompt.txt: To take a PlanningBundle and produce the ExecutablePlan.
       3. `DTM_3_SERVICE_SCAFFOLD`: Implement the PlanFormulationService class and its primary method, formulate_plan.
       4. `DTM_4_SERVICE_LOGIC`: Implement the orchestration logic within the service: call the primary planner, then the critics in parallel, assemble
          the PlanningBundle, call the final planner, and validate the final ExecutablePlan.
       5. `DTM_5_VALIDATION_TEST`: Create the master integration test for this service. It will call plan_formulation_service.formulate_plan(gsb) and
          assert that the output is a valid and strategically sound ExecutablePlan.

   * Workstream B (Systems Engineering - Upgrading the `WorkflowOrchestrator`):
       1. `O1_PLAN_PARSING`: Implement the logic in the WorkflowOrchestrator to parse an ExecutablePlan into its internal graph representation. This will
          be unit-tested using the sample_executable_plan.json fixture.
       2. `O3_FAILURE_DETECTION_STUB`: Implement the simple "zero findings" failure condition.
       3. `O4_ALTERNATIVE_ACTIVATION`: Implement the core logic for state tracking, alternative lookup, and enqueuing fallback tasks. This will be
          validated with a unit test that simulates a task failure on the static fixture.
       4. `O5_HANDLE_DEAD_END`: Implement and test the logic for handling a failed task that has no defined alternative.

   * Verifiable Outcome: Two separate, merged pull requests. One from the Agent team with a fully-tested PlanFormulationService. One from the Systems
     team with a fully unit-tested, graph-aware WorkflowOrchestrator.

  ---

  UPDATE:
  Assumption 1: The Orchestrator is the Sole Owner of the Graph State.
   * The Assumption: We're assuming that the WorkflowOrchestrator is the only component that needs
     to know about the plan's graph structure.
   * The Problem: This is a direct violation of our DDD principles. The LiveRun object is the
     Aggregate Root and the single source of truth for a run's state. The state of the plan's
     execution (e.g., which tasks are pending, running, succeeded, failed) belongs in LiveRun, not
     scattered inside the orchestrator. The orchestrator is an ephemeral "worker" that gets created
      for a run; the LiveRun is the long-lived entity representing the run itself.
   * Information Needed: We need to define the canonical representation of the "Execution Graph
     State" within the LiveRun object itself.

  Assumption 2: The Graph is Only for Failure Handling.
   * The Assumption: My proposal only created a lookup for alternatives. It completely ignored the
     depends_on relationship.
   * The Problem: This only solves half the problem. A true graph executor must also handle
     dependencies to enable parallel execution. For example, if the plan has two independent
     "root" tasks, they should be able to run concurrently. If Task C depends on A and B, it
     should only run after both have succeeded. Our parsing logic must account for this.
   * Information Needed: We need to design a data structure that can efficiently track the
     dependencies of each task and determine when a task is "ready to run."

  Assumption 3: The Agent-Generated `task_id` is Sufficient.
   * The Assumption: We've assumed the agent-generated task_id (e.g., "search_kanda") is the only
     identifier we need.
   * The Problem: What happens if a reflection cycle or a future dynamic planning step wants to
     add a new task to the graph mid-run? How does it generate a unique ID that doesn't conflict
     with the agent's original plan? Furthermore, the orchestrator already has its own internal
     task tracking mechanism (orchestrator_task_id). How do these two ID systems relate?
   * Information Needed: We need a clear policy for task identity.
       1. The agent's task_id should be treated as a "Plan Node ID" or "Logical Task Name". It
          defines the node's role in the strategy.
       2. The orchestrator_task_id is the "Execution Instance ID". It's a unique identifier for a
          specific run of a task. This distinction is crucial if we ever want to support retries
          (a second run of the same logical task).

  Assumption 4: The Plan is Static.
   * The Assumption: The parsing happens once, at the beginning of the execute method.
   * The Problem: The Assessment Reflector agent may, in the future, modify the plan mid-run by
     proposing new tasks with new dependencies. The parsing logic must not just be a one-time
     setup; it needs to be part of a larger state management system that can handle additions to
     the graph.
   * Information Needed: How does a new task get added to the graph state in LiveRun? The
     propose_task method on LiveRun will need to be updated to understand these new graph
     relationships.

  The Iterated Plan for O1_PLAN_PARSING

  This is not a simple parsing step. This is about defining and populating the canonical graph 
  state for the entire run.

  The Correct Location: The logic for parsing the plan and storing the graph state belongs in the
  `LiveRun` class, not the WorkflowOrchestrator.

  The New Plan:

   1. Define the Graph State Schema in `LiveRun`:
       * We will add new attributes to the LiveRun class to hold the graph state. This will be our
         canonical representation.

    1         # In push_search/workflow/run_state.py, inside LiveRun class
    2 
    3         # Stores the canonical Task object, keyed by its logical plan ID
    4         self.plan_graph: dict[str, Task] = {}
    5 
    6         # Tracks the execution status of each logical task
    7         self.plan_graph_status: dict[str, Literal["pending", "running", "succeeded"
      , "failed"]] = {}
    8 
    9         # Pre-computed lookups for efficient execution
   10         self.success_dependents: dict[str, list[str]] = {} # task_id -> list of 
      tasks that depend on it
   11         self.failure_alternatives: dict[str, list[str]] = {} # task_id -> list of 
      tasks that are fallbacks for it

   2. Create a New Method on `LiveRun`: `set_executable_plan`:
       * This method will be the new entry point. It takes the ExecutablePlan (list[Task]) as
         input.
       * Its responsibility will be to perform the parsing and population of the graph state
         attributes defined above. It will iterate through the list of tasks and build the
         plan_graph, plan_graph_status, success_dependents, and failure_alternatives lookups.
       * This method is where the O1_PLAN_PARSING logic will actually be implemented.

   3. Update the `WorkflowOrchestrator`:
       * The orchestrator will no longer have its own graph data structures.
       * At the beginning of its execute method, it will call
         self.run_actor.set_executable_plan(plan).
       * During execution, it will read from the graph state on LiveRun (e.g.,
         self.run_actor.failure_alternatives) to make decisions.

  This revised plan is far more robust. It correctly places the state management responsibility on
   the DDD Aggregate Root (LiveRun), creates a clear and extensible data model for the graph
  state, and simplifies the role of the WorkflowOrchestrator to be a pure executor that reads from
   this canonical state.

----

  Phase 3: Integration and End-to-End Validation

  Goal: Connect the PlanFormulationService to the WorkflowOrchestrator and validate the entire flow.

   * Workstream (Systems & Agent Collab):
       1. `INT_1_CONNECT_SERVICES`: In the main RunLifecycleManager, replace the call to the old single planner agent with a call to the new
          PlanFormulationService.
       2. `INT_2_E2E_TEST`: Create the "Tokyo Fix" end-to-end test. It will call the full system and use mocking to force a web_search failure, asserting
          that the correct alternative task is subsequently executed.

   * Verifiable Outcome: A merged pull request containing the integration code and the passing "Tokyo Fix" E2E test. The MLP is now functionally
     complete.

  ---

  Phase 4: Intelligent Triggers & Observability (Polish)

  Goal: Upgrade the simple failure trigger to be smarter and add the necessary instrumentation.

   * Workstream (Systems Engineering):
       1. `V1_CONSTRAINT_VALIDATOR`: Build and unit-test the standalone constraint validation function.
       2. `V2_INTEGRATE_VALIDATOR`: Replace the "zero findings" stub in the orchestrator with the new, intelligent validator. Update the E2E test to mock
          invalid findings and assert that the fallback is still correctly triggered.
       3. `E1_SEMANTIC_EVENTS`: Instrument the orchestrator and the PlanFormulationService with semantic events for observability.

   * Verifiable Outcome: A final merged pull request. The system is now robust, intelligent, and observable, meeting all project requirements.
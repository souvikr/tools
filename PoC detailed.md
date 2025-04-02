

## Introduction and Objectives

This document outlines a **proof-of-concept chatbot system** for querying a financial reference data repository in natural language. The goal is to enable users to ask questions about financial instruments (bonds, FX, credit products, etc.) and receive accurate, explainable answers. The system integrates a Large Language Model (LLM) interface with both **semantic search** on unstructured data and **structured lookup** on relational data. Key requirements include:

- **OpenAI API (LLM Interface)** – Use a powerful LLM (e.g. GPT-4 via OpenAI API) to interpret queries and generate answers.
    
- **Elasticsearch (Vector DB)** – Leverage Elasticsearch’s vector search capabilities for embedding-based semantic retrieval ([Semantic search with Vector embeddings using Elasticsearch | by BigM | Medium](https://medium.com/@mickey.lubs/semantic-search-with-vector-embeddings-using-elasticsearch-6a47119fac92#:~:text=,apart%20from%20traditional%20search%20mechanism)), to find relevant context or records by meaning rather than exact keywords.
    
- **GraphRAG Knowledge Graph** – Construct a knowledge graph from a subset of an Oracle 19c database (~200 GB of reference data) using GraphRAG techniques. This graph will capture entities (instruments, issuers, ratings, etc.) and their relationships, enabling multi-hop reasoning.
    
- **LangGraph Orchestration** – Utilize LangGraph to orchestrate the workflow: deciding when to query the knowledge graph vs. semantic search, and how to combine results, enabling an _agentic_ retrieval-augmented generation flow.
    
- **Infrastructure Constraints** – The solution will be deployed on-premises on RHEL servers (500 GB RAM, CPU-only, no GPU). Therefore, it must optimize for speed in embedding generation and search without GPU acceleration.
    

The chatbot should handle queries like _“Given 20 ISINs, find the Moody’s and Fitch ratings for each.”_ by understanding the query, retrieving the relevant structured data (ratings for each ISIN), possibly augmenting with definitions or context via semantic search, and producing a clear, explained answer.

## High-Level Architecture Overview

At a high level, the system is composed of several interconnected components working in a pipeline (see **Figure 1**). The architecture blends **vector-based retrieval** with **knowledge-graph-based retrieval**, orchestrated by a graph-defined workflow. The main components are:

- **User Interface & LLM**: The user poses a natural language question to the chatbot. The question is processed by an LLM (via the OpenAI API) which serves as the conversational brain – interpreting the query and later generating the answer.
    
- **LangGraph Orchestrator**: The brain of the system’s logic. LangGraph defines the workflow as a directed graph of steps/nodes (each node is an operation or “tool”). It manages the flow of information between the LLM and the search tools. LangGraph supports conditional branching and stateful loops ([Building an Agentic RAG with LangGraph: A Step-by-Step Guide | by Wendell Rodrigues, Ph.D. | Medium](https://medium.com/@wendell_89912/building-an-agentic-rag-with-langgraph-a-step-by-step-guide-009c5f0cce0a#:~:text=What%20is%20LangGraph%3F)), allowing the chatbot to decide whether to fetch more data or use different tools based on the query. In essence, it enables an **agentic RAG** approach where the LLM can iteratively call on tools and refine the query if needed.
    
- **Knowledge Graph (GraphRAG)**: A **knowledge graph** derived from the Oracle 19c reference data. This graph encodes the structured relationships in the data (e.g. instruments, their issuers, ratings from agencies, currencies, etc.). It is built using the GraphRAG methodology: ingesting the structured data into a graph format, possibly clustering related entities and summarizing as needed. The knowledge graph allows the system to retrieve facts via graph traversal instead of text search. This addresses complex queries that require joining data across multiple tables or “connecting the dots” between entities – something that basic vector search might struggle with ([Welcome - GraphRAG](https://microsoft.github.io/graphrag/#:~:text=real,For)). For example, an instrument node might connect to a “Moody’s rating” node and a “Fitch rating” node, enabling direct lookup of those values.
    
- **Vector Semantic Index (Elasticsearch)**: A **semantic search index** built on Elasticsearch, which stores embeddings of relevant textual data. Each piece of information (such as instrument descriptions, rating definitions, or other reference text) is converted into a high-dimensional vector. Elasticsearch’s kNN capabilities allow fast similarity matching: given a query embedding, it can retrieve the most semantically similar documents or entries ([How to deploy NLP: Text embeddings and vector search - Elasticsearch Labs](https://www.elastic.co/search-labs/blog/how-to-deploy-nlp-text-embeddings-and-vector-search#:~:text=Vector%20similarity%20search%20or%2C%20as,using%20a%20text%20embedding%20model)). This is useful for questions that are not exact matches to structured fields or when the user asks in a roundabout way. For instance, if a user asks for “investment grade bonds by Company X”, the term “investment grade” might be captured via semantic similarity (finding bonds with ratings A and above). The vector index complements the knowledge graph by catching nuances in phrasing and providing supporting context snippets.
    
- **Oracle Database (Source)**: The original **Oracle 19c relational database** holding ~5 TB of enterprise reference data (with a 200 GB subset relevant to this PoC). It contains structured records of financial instruments and their attributes (e.g., ISIN codes, issuer info, credit ratings from various agencies, currency, maturity dates, etc.). For the PoC, this data is **extracted and transformed** into the knowledge graph and the semantic index (rather than being queried live at runtime). This ensures query-time performance is fast and offloads heavy joins or text processing from the operational DB.
    

Below is a conceptual diagram of the interactions between these components in the query workflow:

```
User Query --> [LangGraph Workflow] --> 
    [LLM Query Analyzer Node] --(identifies entities--> e.g. ISINs)--> 
        [Graph Query Node (Knowledge Graph)] --> structured results (ratings, etc)
        [Vector Search Node (Elasticsearch)] --> relevant context snippets
    [Results Integration] --> [LLM Answer Generation Node] --> Final Answer to User
```

In this flow, LangGraph manages the calls: the LLM may first classify or parse the query, then LangGraph triggers searches (graph or vector) as needed, and finally the LLM composes the answer using all retrieved information.

**Figure 1: System Architecture (LLM + Knowledge Graph + Vector DB)**

([Welcome - GraphRAG](https://microsoft.github.io/graphrag/)) _An LLM-generated knowledge graph example (from GraphRAG) where nodes represent entities and colors denote communities of related nodes ([Welcome - GraphRAG](https://microsoft.github.io/graphrag/#:~:text=GraphRAG%20is%20a%20structured%2C%20hierarchical,based%20tasks)). In our system, a knowledge graph encodes financial instruments and their relationships (e.g. ratings, issuers), enabling structured multi-hop retrieval._

## Data Extraction and Knowledge Graph Construction (GraphRAG Pipeline)

**Source Data:** The Oracle 19c database provides the authoritative data about financial instruments. For this PoC, we identify the subset of tables and records (≈200 GB) most relevant to user queries (e.g., bond instrument master data, rating tables, issuer information, currency reference, etc.). This subset is exported from Oracle for building the PoC indexes. The extraction can be done via Oracle SQL dumps or an ETL pipeline that pulls specific columns (like ISIN, instrument name, rating codes, etc.).

**Graph Schema Design:** Using the extracted structured data, we construct a **knowledge graph** that mirrors the relational structure in a more semantic form. Each major entity type becomes a node class in the graph, and foreign-key relationships become edges. For example:

- **Instrument Node**: represents a financial instrument (bond, FX contract, etc.), identified by keys like ISIN or instrument ID. It will have properties such as name, type, issue date, etc., and edges to related entities.
    
- **Issuer/Entity Node**: represents the issuing entity (company or government). An Instrument node connects to an Issuer node via an “issued_by” relationship.
    
- **Rating Nodes**: It may be useful to represent credit ratings as nodes or attributes. One approach is to have a node for each _Rating Assignment_ (e.g., a specific rating given by an agency at a point in time), connecting to the Instrument and to the _Rating Agency_ node (“Moody’s”, “Fitch” as agency nodes). Alternatively, simpler for this PoC, we can store current rating values as properties on the Instrument node (e.g., `instrument.has_rating_Moodys = A2`). For multi-hop reasoning and explainability, representing the rating as a node linked to the agency might be better (so the chatbot can traverse “Instrument -> Moody’s -> RatingValue”).
    
- **Reference Entities**: Other reference data can be nodes too – e.g., Currency nodes (USD, EUR) linked to instruments, or Product Category nodes (Bond, Swap, Equity) to classify instruments.
    

**GraphRAG Methodology:** GraphRAG typically involves using LLMs to extract entities and relations from text ([GraphRAG Explained: Enhancing RAG with Knowledge Graphs | by Zilliz | Medium](https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1#:~:text=this%20input%20data,can%20effectively%20discover%20community%20structures)), but in our case the data is already structured. We leverage GraphRAG concepts to **automatically construct and enrich the graph**. This includes:

- _Entity and Relationship Extraction_: We treat the rows in Oracle tables as “text units” in a sense – but since schema is known, we map columns to entity attributes and table relations to edges. We might still use an LLM to **label or describe relationships** for documentation. For instance, have GPT-4 generate a short description of what each relationship means to store as metadata (helpful for prompting later). However, the core graph is built directly from the relational data.
    
- _Community Detection (Clustering)_: With a large graph of entities, GraphRAG suggests using algorithms like **Leiden clustering** to find densely connected groups ([GraphRAG Explained: Enhancing RAG with Knowledge Graphs | by Zilliz | Medium](https://medium.com/@zilliz_learn/graphrag-explained-enhancing-rag-with-knowledge-graphs-3312065f99e1#:~:text=3,depth%20analysis)). In financial data, clusters might form around issuers (all instruments of an issuer), or by instrument type, etc. We can perform this to identify communities (e.g., all bonds issued by the same company could be a community). Summaries of communities can then be generated (e.g., an LLM summarizing “Community = {Issuer X and its 50 bonds, with various ratings…}”). This is more relevant for **global or analytical queries** (“What are the main themes in the dataset?”), which might be beyond the immediate PoC needs, but it’s a capability we can include for completeness.
    
- _Knowledge Graph Storage_: For the PoC, given 500 GB RAM, one option is to use an in-memory graph database or triple store. A lightweight approach is to use something like **NetworkX** (Python) for simple graph queries in memory (sufficient for PoC scale), or a proper graph database like **Neo4j** or **TigerGraph** for more complex querying if needed. Neo4j would allow using Cypher queries to retrieve data (e.g., find all ratings for a list of ISINs). The graph could also be stored in Elasticsearch if using Elastic’s **graph capabilities** or as JSON docs, but a specialized graph DB is more natural for traversal queries.
    

The output of this stage is a **populated knowledge graph** that the chatbot can query. This graph gives a structured, connected view of the data, which will be crucial for questions that require joining information (e.g., find all bonds (Instrument) for a given issuer that have a certain rating from Moody’s – this becomes a traversal Issuer → Instrument → Rating). GraphRAG’s advantage is that it “broadens the horizon” of retrieval by integrating diverse knowledge through graph structure ([GraphRAG: Improving RAG with Knowledge Graphs](https://www.vellum.ai/blog/graphrag-improving-rag-with-knowledge-graphs#:~:text=Fundamentally%2C%20GraphRAG%20is%20a%20new,holistic%20view%20of%20your%20data)), whereas vector search alone might miss such multi-hop connections. Fundamentally, **GraphRAG augments a standard RAG pipeline with a knowledge graph** to improve accuracy and multi-step reasoning ([GraphRAG: Improving RAG with Knowledge Graphs](https://www.vellum.ai/blog/graphrag-improving-rag-with-knowledge-graphs#:~:text=A%20basic%20GraphRAG%20architecture%20that,in%20addition%20to%20vector%20stores)).

## Semantic Search Index and Embeddings (Elasticsearch Vector DB)

In parallel with building the knowledge graph, we create a **semantic vector index** of relevant textual data to support natural language queries. This component ensures that if a user’s query doesn’t directly match a structured field, the system can still find the right information by meaning. Key steps and considerations:

- **Document Preparation**: We derive textual “documents” from the reference data to index in Elasticsearch. For example, for each Instrument we can generate a short description that includes key fields: _“Bond ISIN US1234567890 – Issuer: ACME Corp – Moody’s Rating: A2 – Fitch Rating: A – Maturity: 2028 – Currency: USD”_. Similarly, we might index descriptions of issuers (company profiles) or definitions of rating grades (what does A2 mean?). We should also include any unstructured data available, like product descriptions or market commentary, if provided in the dataset. Each such document is tagged with an ID or metadata linking it to the graph entities (so if we retrieve a doc about ISIN X, we know that corresponds to the Instrument node X in the graph).
    
- **Embedding Generation**: Each document string is converted to a numeric embedding vector in high-dimensional space, using a **text embedding model**. We want the fastest feasible method here. Options include:
    
    - _OpenAI Embeddings API_: Use a model like `text-embedding-ada-002` to embed documents. This ensures high-quality embeddings but would rely on API calls and may be slower or costly for 200GB of data. Likely we prefer a local solution for speed at this scale.
        
    - _Local Sentence Transformer_: Use a pre-trained **Sentence-BERT** or similar model on CPU. For example, **MiniLM** or **mpnet** models offer 300-768 dimensional embeddings and are optimized for semantic similarity ([How to deploy NLP: Text embeddings and vector search - Elasticsearch Labs](https://www.elastic.co/search-labs/blog/how-to-deploy-nlp-text-embeddings-and-vector-search#:~:text=The%20first%20step%20is%20to,For%20our%20model%20we%20use)). These can be run locally, possibly using PyTorch with CPU optimizations or via Elasticsearch’s built-in model inference. (Elasticsearch supports deploying models via its ML inference plugin ([How to deploy NLP: Text embeddings and vector search - Elasticsearch Labs](https://www.elastic.co/search-labs/blog/how-to-deploy-nlp-text-embeddings-and-vector-search#:~:text=1,model)), allowing embeddings to be generated as documents are ingested. We could load a model like `msmarco-MiniLM-L12-cos-v5` which maps text to a 384-dimensional vector ([How to deploy NLP: Text embeddings and vector search - Elasticsearch Labs](https://www.elastic.co/search-labs/blog/how-to-deploy-nlp-text-embeddings-and-vector-search#:~:text=The%20first%20step%20is%20to,For%20our%20model%20we%20use)).)
        
    - _Optimization_: Since we have no GPU, we will maximize CPU throughput: enabling multiple threads for inference ([How to deploy NLP: Text embeddings and vector search - Elasticsearch Labs](https://www.elastic.co/search-labs/blog/how-to-deploy-nlp-text-embeddings-and-vector-search#:~:text=This%20time%2C%20,inference%20threads%20with%20inference_threads%20parameter)), batching embeddings, and perhaps quantizing the model (e.g., use 8-bit quantization to speed up compute). The 500 GB RAM allows us to hold large batches or even the whole model in memory to avoid disk bottlenecks.
        
- **Indexing in Elasticsearch**: We create an Elasticsearch index with a **dense vector field** to store embeddings (e.g., a 384-d vector per document). We enable approximate **k-Nearest Neighbors (kNN)** search (Elasticsearch uses algorithms like HNSW for fast vector similarity search). We also store the original text or key fields alongside the vector for result context. Elasticsearch will serve as our **vector database**, capable of retrieving top-N similar documents for any query vector. Semantic vector search “goes beyond keyword search” by retrieving information that is contextually relevant even if wording differs ([How to deploy NLP: Text embeddings and vector search - Elasticsearch Labs](https://www.elastic.co/search-labs/blog/how-to-deploy-nlp-text-embeddings-and-vector-search#:~:text=Vector%20similarity%20search%20or%2C%20as,using%20a%20text%20embedding%20model)). This is crucial for understanding user questions in finance, where terminology can vary. For example, a user might ask, “What’s the **Fitch** and **Moody’s** on these bonds?” – the embeddings should capture that this refers to credit ratings, even if the database field is called “Rating_Agency_Value”.
    
- **Query-time use**: At runtime, when the user asks a question, the system will also embed the **user’s query** (using the same model) into a vector. This query vector is sent to Elasticsearch to find the most semantically similar documents. Because we index structured data in sentence form, the search results will often correspond to the relevant instruments or definitions. For instance, given the query “Moody’s and Fitch ratings for ISIN US1234567890”, the vector search might retrieve the document for that ISIN’s description (since it contains those terms), or even if the query was phrased less explicitly, it would surface the right records by semantic matching.
    
- **Performance**: The vector search is designed for speed. With HNSW indexing and our relatively short vectors (few hundred dimensions), a query should return results in tens of milliseconds even with millions of documents. The key is that all embeddings are pre-computed and indexed. If the dataset is extremely large (hundreds of millions of records), we might limit semantic search to certain subsets (like only index the latest data or summary per issuer) to keep it efficient. However, for PoC and even beyond, Elasticsearch can scale out to handle quite large indexes with the given RAM.
    
- **Iteration & Mocking**: During initial development, to **iterate quickly**, we do not need to index the full 200 GB. We can start with a **small sample** (e.g. 1% of the data or a few thousand records) to ensure the pipeline works. This can be done by sampling a variety of instruments and their ratings. Additionally, for testing specific queries, we can **mock the vector search** by manually creating a few example documents that we know should be retrieved. For instance, we can insert a few records for known ISINs with known ratings to test the query “Find Moody’s and Fitch for these ISINs” without indexing everything. This speeds up iteration. Once the logic is confirmed, we then scale up the embedding indexing process for more data. Elasticsearch also allows incremental indexing, so we can gradually feed more records and monitor search accuracy.
    

In summary, the Elasticsearch-based semantic search provides a **flexible retrieval mechanism** that catches user intents in natural language ([Semantic search with Vector embeddings using Elasticsearch | by BigM | Medium](https://medium.com/@mickey.lubs/semantic-search-with-vector-embeddings-using-elasticsearch-6a47119fac92#:~:text=,apart%20from%20traditional%20search%20mechanism)). It works hand-in-hand with the knowledge graph: the vector search might find the relevant instrument entries and any explanatory text, while the knowledge graph provides the authoritative structured facts for those entries.

## Orchestration with LangGraph (Workflow & Integration)

With both the knowledge graph and vector search in place, the **LangGraph** framework coordinates how each user query is handled. LangGraph allows us to define a **graph of operations** that the system will traverse for each query, enabling dynamic decision-making. The orchestration logic is designed as follows:

- **Query Analysis Node (LLM)**: The first step is to interpret the user’s natural language query. We use the OpenAI LLM (GPT-4 or GPT-3.5) to parse the query intent and entities. For example, if the query is _“Given 20 ISINs, find the Moody’s and Fitch ratings for each”_, the LLM (or possibly a simple regex script) will recognize that the user provided a list of 20 ISIN codes (which follow a known pattern). It will also classify the query as one that requires _structured data retrieval_ (credit ratings) for specific identifiers. This analysis can be done via a prompt like: _“Extract any financial identifiers from the user query and determine the information requested.”_ The output could be a JSON listing the ISINs and a label like `query_type: lookup_ratings`.
    
- **Decision & Branching**: Based on the analysis, LangGraph decides which branches of the workflow to activate. LangGraph supports **conditional edges and loops ([Building an Agentic RAG with LangGraph: A Step-by-Step Guide | by Wendell Rodrigues, Ph.D. | Medium](https://medium.com/@wendell_89912/building-an-agentic-rag-with-langgraph-a-step-by-step-guide-009c5f0cce0a#:~:text=operation))**. In this case, detecting explicit identifiers (ISINs) triggers the **Graph lookup branch**, because we can directly query our knowledge graph for those items. If instead the query was something like “What are the highest Moody’s ratings among ACME Corp’s bonds?”, the analysis would identify an issuer name (ACME Corp) and a concept of “highest rating”, which might require first finding all bonds of that issuer (graph query) and then maybe filtering or sorting by rating (logic that the LLM can do once data is retrieved). If a query is more conceptual or doesn’t contain specific ids (e.g. “Explain what Moody’s rating means for a bond”), the system would lean on the **semantic search branch** to fetch explanatory content (like definitions of Moody’s ratings) and maybe less on the graph.
    
- **Graph Retrieval Node**: When invoked, this node will perform a query on the **knowledge graph**. We can implement this as a function or tool that takes entities (like a list of ISINs or an issuer name) and queries the graph database for related info. In our example, it will take the 20 ISINs and retrieve their Moody’s and Fitch ratings. If using Neo4j, a Cypher query could be constructed: `MATCH (inst:Instrument)-[r1:RATED_BY {agency:'Moody'}]->(ratingM:Rating), (inst)-[r2:RATED_BY {agency:'Fitch'}]->(ratingF:Rating) WHERE inst.isin IN [ ... list of ISINs ... ] RETURN inst.isin, ratingM.value, ratingF.value;`. This would return a table of ISIN with its two ratings. If using an in-memory structure, we’d simply look up each instrument in a dictionary or graph adjacency list. **LangGraph** would pass the results along as structured data (perhaps as a Python object or JSON).
    
- **Vector Search Node**: In parallel (or if graph didn’t have a direct hit), the LangGraph workflow can also invoke the **Elasticsearch semantic search**. For the ISIN query example, this might not even be necessary (since we have exact matches). But for completeness, suppose some ISIN in the list is not found in the graph (maybe it’s out of the subset). The vector search could be a fallback: it would embed that ISIN or related text and attempt to find any mention of it in the index. More commonly, for a query that is phrased in a descriptive way, the vector search node will retrieve top relevant texts. LangGraph can be configured to always do a semantic search to gather _contextual sentences_ that could be used in the answer for explanation. For example, if the user’s query is purely a lookup, the graph gives the raw numbers (ratings). The vector search might retrieve an official definition of what an “A2” rating means from documentation. This extra context can make the final answer more informative (“...Moody’s rating A2 (which is in the upper-medium grade) ...”).
    
- **Iterative Agent Loop**: LangGraph allows the LLM to behave in an **agentic** manner ([Building an Agentic RAG with LangGraph: A Step-by-Step Guide | by Wendell Rodrigues, Ph.D. | Medium](https://medium.com/@wendell_89912/building-an-agentic-rag-with-langgraph-a-step-by-step-guide-009c5f0cce0a#:~:text=An%20Agentic%20RAG%20builds%20on,makes%20decisions%20during%20the%20workflow)) ([Building an Agentic RAG with LangGraph: A Step-by-Step Guide | by Wendell Rodrigues, Ph.D. | Medium](https://medium.com/@wendell_89912/building-an-agentic-rag-with-langgraph-a-step-by-step-guide-009c5f0cce0a#:~:text=What%20is%20LangGraph%3F)). This means after the initial retrieval, the LLM might decide it needs more information. For instance, if some ISIN wasn’t found, the LLM could ask a follow-up internally like “I couldn’t find ISIN X, maybe it’s new – should I search a different source?” In an advanced setup, we might include a fallback tool (like a direct SQL query to Oracle or an external API) and loop back. For the PoC, we can keep it simpler: assume the data is mostly in our index. But LangGraph’s design enables adding such nodes easily. Each node can be connected in a cycle: `agent -> tool -> agent` where the agent (LLM) checks if the answer is complete or if another tool invocation is needed ([Building an Agentic RAG with LangGraph: A Step-by-Step Guide | by Wendell Rodrigues, Ph.D. | Medium](https://medium.com/@wendell_89912/building-an-agentic-rag-with-langgraph-a-step-by-step-guide-009c5f0cce0a#:~:text=workflow.add_edge%28START%2C%20%22agent%22%29%20%20,Cycle%20between%20tools%20and%20agent)). We might not need complex loops for straight Q&A, but this framework is ready for more complex dialogues.
    
- **Result Aggregation**: Once the Graph and/or Vector search nodes have returned results, LangGraph combines them. This could be as simple as collecting all retrieved data into a single context dictionary. For example, we’ll have a list of ISINs with ratings from the graph, and maybe some explanatory text from vector search. The LangGraph workflow then proceeds to the final node: Answer Generation.
    
- **Answer Generation Node (LLM)**: Here we construct a prompt for the LLM to formulate the final answer. The prompt will include the **structured results** (e.g., a table or bullet list of each ISIN and its ratings) and any additional context (e.g., “Moody’s ratings are ... Fitch ratings are ...” if needed). We instruct the LLM to present the information clearly, perhaps in a tabular format or a few sentences, and to include any necessary explanation for clarity. Because we want **explainable answers**, the prompt can say: _“Using the data provided, answer the user. Explain any relevant terms and ensure the source of the data (the reference database) is apparent in the answer.”_ The LLM will then produce a response. For instance, it might output: _“Here are the ratings for the requested ISINs: \n- ISIN1: Moody’s A2, Fitch A (meaning Moody’s A2 which is a good credit quality, and Fitch A which is equivalent grade)… \n- ISIN2: Moody’s Baa1, Fitch BBB (Moody’s Baa1 = lower medium grade, Fitch BBB = equivalent)…_” and so on. The answer should be structured (perhaps as a list or table) for readability, since the user provided a list. The LLM’s natural language ability will ensure the answer isn’t just raw data but is contextualized (e.g. noting if any ISIN wasn’t found or if ratings are as of a certain date, if that info was in the data).
    
- **Returning Answer**: LangGraph then returns the LLM’s answer back to the user through the interface. The state can be preserved if the user asks a follow-up question in the same session (thanks to LangGraph’s stateful memory). For example, if the user then asks “Which of those is the highest rated by Moody’s?”, the system can use the prior results (stored in memory) to quickly answer or at least not start from scratch. The orchestrator would recognize the context (the list of ISINs) from memory and directly analyze that.
    

**Integration of GraphRAG and LangGraph:** In this design, GraphRAG provides the knowledge graph _data foundation_, and LangGraph provides the _control logic_. GraphRAG’s principles (like local vs global queries) inform how we use the graph: a query about specific identifiers is handled like **GraphRAG local search**, focusing on those particular nodes and their neighbors ([Welcome - GraphRAG](https://microsoft.github.io/graphrag/#:~:text=,added%20context%20of%20community%20information)). A broader query (e.g. “What are the main rating distributions for ACME Corp?”) might be handled more like **global search**, utilizing summaries or aggregations (which we could generate via communities). LangGraph doesn’t inherently know about GraphRAG, but we encode those strategies into the workflow. Essentially, we are **combining vector RAG and GraphRAG**: the LangGraph agent decides, for each query, whether to use the vector store, the knowledge graph, or both, to retrieve information, and then uses the LLM to synthesize the answer. This hybrid approach ensures both **depth (structured accuracy)** and **breadth (semantic understanding)** in retrieval ([GraphRAG: Improving RAG with Knowledge Graphs](https://www.vellum.ai/blog/graphrag-improving-rag-with-knowledge-graphs#:~:text=Lately%2C%20there%27s%20been%20a%20lot,in%20a%20more%20declarative%20way)) ([GraphRAG: Improving RAG with Knowledge Graphs](https://www.vellum.ai/blog/graphrag-improving-rag-with-knowledge-graphs#:~:text=Vectors%20and%20knowledge%20graphs%20are,they%20complement%20each%20other%20well)).

## Example Use Case Flow: Query for ISIN Ratings

To illustrate the end-to-end operation, consider the example query:

**User asks:** _“Given these 20 ISINs, find the Moody’s and Fitch ratings for each.”_ (Assume the user provides a list of 20 specific ISIN codes in the query.)

**Step 1: Query Analysis** – The LLM (via a prompt or a parsing function) identifies the ISINs in the query and understands the user wants credit ratings from two specific agencies for each provided instrument. It classifies this as a straightforward data retrieval query (no complex reasoning or multi-hop beyond finding each instrument’s ratings).

**Step 2: Knowledge Graph Lookup** – The system, through LangGraph, invokes the graph query node with the list of ISINs. The knowledge graph is searched for each ISIN node and the connected “Moody’s rating” and “Fitch rating” values. Suppose in the graph each Instrument node has properties or linked nodes for these ratings; the query results in a set of (ISIN -> MoodyRating -> FitchRating) tuples. For example:

```
[
  {isin: "US1234567890", moodys: "A2", fitch: "A"}, 
  {isin: "US0987654321", moodys: "Baa1", fitch: "BBB"}, 
  ... (18 more)
]
```

If any ISIN is not found, that might be noted (e.g., “not in database”).

**Step 3: Semantic Search (if needed)** – In this particular use case, the system may skip semantic vector search because the query is explicit and we trust the graph results. However, for robustness, it could also take the whole query (or each ISIN) and perform a vector search. The vector search might retrieve a small description of each bond (which includes those ratings in text) or perhaps a definition of what “A2” means. For instance, it might retrieve a document: _“ISIN US1234567890: Bond issued by ACME Corp, Moody’s A2, Fitch A, etc.”_ which corroborates the graph. This is redundant but can be used to double-check or to have a natural language snippet about each instrument. It might also retrieve a general document like “Moody’s rating scale: A2 means …” which could be useful if the user might need clarification. For our immediate answer, we likely won’t enumerate definitions unless asked, but having them can help the LLM phrase the answer in an explanatory way.

**Step 4: Compile Context for LLM** – LangGraph collects the results. Now we have a structured list of ratings per ISIN from the graph, and possibly some textual context (like a few example descriptions) from Elastic. We construct the final prompt for answer generation. This could be a system or assistant prompt that says: _“You are a financial assistant. The user asked for Moody’s and Fitch ratings for a list of ISINs. Here is the data we found:”_, followed by a formatted list of the ISINs and their ratings. We might format it as a markdown table in the prompt to encourage a neat answer (since the user likely expects a list). For example, we give the LLM something like:

```
ISIN | Moody's Rating | Fitch Rating
---|---|---
US1234567890 | A2 | A
US0987654321 | Baa1 | BBB
... (and so on for all 20)
```

And then: _“Provide the ratings for each ISIN in a clear format. If needed, briefly explain the ratings.”_

**Step 5: LLM Generates Answer** – The LLM uses the provided structured data to generate the answer. Thanks to the structured input, it may output a similar table or a list. For example, it might respond in markdown:

“**Ratings for the given ISINs:**

- **US1234567890** – Moody’s: **A2**, Fitch: **A**
    
- **US0987654321** – Moody’s: **Baa1**, Fitch: **BBB**
    
- ... (and so forth for all ISINs)
    

All the above ratings were retrieved from the financial reference database. _Moody’s A2_ corresponds to a high-quality (upper-medium grade) rating, and _Fitch A_ is an equivalent high credit quality rating. Each ISIN’s ratings are up-to-date as per the reference data.”

This answer not only lists each item clearly but also adds a brief explanation of what those ratings imply, making it **explainable and user-friendly**. The mention of “retrieved from the reference database” is an example of a provenance hint, giving the user confidence in the source. (In a more advanced setup, we could even cite the source or provide a link to the data, but since this is an internal system, a general statement suffices.)

**Step 6: User Receives Answer** – The final answer is sent back to the user through the chatbot UI. If the user has follow-up questions (e.g., “Which of these bonds has the highest Fitch rating?”), the conversation context (the list of ISINs and their ratings) is maintained by LangGraph’s memory. The next query can be answered by analyzing the stored results (the LLM could sort the ratings it has without even querying again). This demonstrates how the combination of structured data and intelligent orchestration handles both direct queries and conversational follow-ups efficiently.

## Component Integration and Performance Considerations

**Local Deployment**: All components will run on local RHEL servers. The OpenAI API calls are external (requiring internet), but if needed for completely offline deployment, one could substitute the OpenAI LLM with a smaller local model (though with 500 GB RAM, hosting a large model is possible but not trivial without GPUs). For the PoC, we assume internet access for API. Elasticsearch will run on the server (maybe a small cluster if needed for performance). The graph database or in-memory graph runs on the same server, taking advantage of the ample RAM.

**Speed Optimizations**: The design prioritizes speed, especially in the embedding and search steps:

- We pre-index data so that at query time, retrieval is fast (O(ms) for both vector search and graph lookup).
    
- Embeddings are precomputed offline; if new data arrives, it can be indexed in the background, avoiding delays during user interaction.
    
- The LangGraph orchestration adds a bit of overhead (calling multiple components), but each call is optimized (e.g., parallel calls can be made if we know both graph and vector should be queried; LangGraph could spawn them concurrently and wait for both).
    
- The most time-consuming step is likely the **LLM call** for answer generation, which with OpenAI API might be a few hundred milliseconds to a couple seconds depending on answer length. This is usually acceptable for a chatbot. The earlier steps (analysis, retrieval) will be tuned to be well under 1 second combined. Thus, the user should experience a response in perhaps ~2 seconds for straightforward queries, which is reasonable for an interactive system.
    

**Scalability & Next Steps**: While this is a PoC, the architecture is designed to scale:

- More data can be added to the knowledge graph incrementally (the graph DB or triple store can be updated with new nodes/edges as the Oracle DB grows).
    
- The Elasticsearch index can scale horizontally if needed (sharding by instrument type or date, etc.), still leveraging vector search for semantics.
    
- Additional **knowledge sources** can be plugged in: e.g., if we later include unstructured documents (like bond prospectuses or news articles), we simply embed and index them in Elastic. The LLM could then retrieve both the structured facts and relevant passages from text, merging them in answers.
    
- LangGraph makes it relatively easy to add new tools. For instance, one could add a **Calculator node** if users ask things like “What’s the average Moody’s rating of these bonds?” (not a straightforward average since ratings are categorical, but the idea is any computation or external call can be a tool node).
    
- We also ensure that everything is logged and observable: LangGraph’s flow can be traced for debugging (which node executed, what it returned, etc.), which is helpful in a PoC to tune the prompts and logic.
    

## Conclusion

This PoC design demonstrates a **hybrid chatbot system** that marries the strengths of vector semantic search and knowledge graphs to handle complex queries on financial reference data. By using **GraphRAG** principles, we capture the structured knowledge in a graph format, enabling the LLM to reason over linked data (e.g., instruments to ratings to issuers). By leveraging **Elasticsearch** for fast semantic lookup, we ensure the chatbot can handle natural language variations and fetch explanatory context. **LangGraph** orchestrates these components in a controlled, modular workflow ([Building an Agentic RAG with LangGraph: A Step-by-Step Guide | by Wendell Rodrigues, Ph.D. | Medium](https://medium.com/@wendell_89912/building-an-agentic-rag-with-langgraph-a-step-by-step-guide-009c5f0cce0a#:~:text=What%20is%20LangGraph%3F)), allowing the system to dynamically decide how to answer a query – whether by direct lookup, searching related information, or iterating with the user. The result is a chatbot that can provide **accurate, explainable answers** for queries like the example given, and can be extended to a wide range of financial data questions.

In summary, the system architecture is designed for **speed, accuracy, and clarity**: speed via precomputation and efficient search, accuracy via grounded data from the knowledge graph, and clarity via the LLM’s natural language explanations augmented by relevant context. This PoC will serve as a foundation, upon which additional features (broader queries, real-time data updates, enhanced explanations) can be built to support users in exploring and understanding their financial reference data.

**Sources:** The design draws on modern RAG techniques and frameworks, including Microsoft Research’s GraphRAG which _“uses knowledge graphs to provide substantial improvements in question-and-answer performance when reasoning about complex information”_ ([Welcome - GraphRAG](https://microsoft.github.io/graphrag/#:~:text=real,For)), and LangChain’s LangGraph which enables _“stateful, multi-step applications that integrate LLMs with external tools”_ via a graph workflow ([Building an Agentic RAG with LangGraph: A Step-by-Step Guide | by Wendell Rodrigues, Ph.D. | Medium](https://medium.com/@wendell_89912/building-an-agentic-rag-with-langgraph-a-step-by-step-guide-009c5f0cce0a#:~:text=What%20is%20LangGraph%3F)). By combining these with Elasticsearch’s semantic vector search (where _“each document or item becomes a vector in a multi-dimensional space, preserving context and nuances”_ ([Semantic search with Vector embeddings using Elasticsearch | by BigM | Medium](https://medium.com/@mickey.lubs/semantic-search-with-vector-embeddings-using-elasticsearch-6a47119fac92#:~:text=,apart%20from%20traditional%20search%20mechanism))), we achieve a robust hybrid solution tailored to our financial data use cases.
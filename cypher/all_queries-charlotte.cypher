//
// This file contains all queries of the README and some additional ones
// Be aware that some might change your data!
//

// Show Operation Point Names and limit the number of returned OPs to 10:
MATCH (op:OperationalPointName) RETURN op LIMIT 10;

// Show OPs and limit the number of returned sections to 50:
MATCH (op:OperationalPoint) RETURN op LIMIT 50;

// Show OperationalPoints and Sections, have a look how those two queries defer!
MATCH path=(:OperationalPoint)--(:OperationalPoint) RETURN path LIMIT 100;
MATCH path=(:OperationalPoint)-[:SECTION]->(:OperationalPoint) RETURN path LIMIT 100;

// using the WHERE clause in two different way:
MATCH (op:OperationalPoint WHERE op.id='SECst') RETURN op;
MATCH (op:OperationalPoint) WHERE op.id='SECst' RETURN op;

// Profile and explain some of the queries to see their execution plans:
PROFILE MATCH (op:OperationalPoint{id:'DE000BL'}) RETURN op;
PROFILE MATCH (op:OperationalPoint) WHERE op.id='DE000BL' RETURN op;

EXPLAIN MATCH (op:OperationalPoint  {id:'DE000BL'}) RETURN op;
EXPLAIN MATCH (op:OperationalPoint) WHERE op.id='DE000BL' RETURN op;

// Fixing some gaps (see README for more information)








///////////////////////////////////////////////
//
// Why are we using a path here?
//
//////////////////////////////

// DK00320 - German border gap
MATCH 
  sg=(op1:OperationalPoint WHERE op1.id STARTS WITH 'DE')-[:SECTION]-(op2:OperationalPoint WHERE op2.id STARTS WITH 'EU'),
  (op3:OperationalPoint WHERE op3.id STARTS WITH 'DK')
WITH op2, op3, point.distance(op3.geolocation, op2.geolocation) AS distance
ORDER BY distance LIMIT 1
MERGE (op3)-[:SECTION {sectionlength: distance/1000.0, fix: true}]->(op2);


///////////////////////////////////////////////
//
// Why are we using a path here?
//
//////////////////////////////
// DK00200 - Nyborg gap
MATCH 
  sg=(op1:OperationalPoint WHERE op1.id = 'DK00200'),
  (op2:OperationalPoint)-[:NAMED]->(opn:OperationalPointName WHERE opn.name = "Nyborg")
MERGE (op1)-[:SECTION {sectionlength: point.distance(op1.geolocation, op2.geolocation)/1000.0, fix: true}]->(op2);

// EU00228 - FR0000016210 through the channel
MATCH 
  (op1:OperationalPoint WHERE op1.id STARTS WITH 'UK')-[:SECTION]-(op2:OperationalPoint WHERE op2.id STARTS WITH 'EU'),
  (op3:OperationalPoint WHERE op3.id STARTS WITH 'FR')
WITH op2, op3, point.distance(op3.geolocation, op2.geolocation) AS distance
ORDER BY distance LIMIT 1
MERGE (op3)-[:SECTION {sectionlength: distance/1000.0, fix: true}]->(op2);

// Find not connected parts for Denmark --> Also try other coutries like DE, FR, IT and so on.
MATCH path=(a:OperationalPoint WHERE NOT EXISTS{(a)-[:SECTION]-()})
WHERE a.id STARTS WITH 'DK'
RETURN path;

// or inside the complete dataset
MATCH path=(a:OperationalPoint WHERE NOT EXISTS{(a)-[:SECTION]-()})
RETURN path;

///////////////////////////////////////////////
//
// This is repeated later on
//
//////////////////////////////

// Set additional traveltime parameter in seconds for a particular section --> requires speed and 
// sectionlength properties set on this section!
MATCH (:OperationalPoint)-[r:SECTION]->(:OperationalPoint)
WHERE r.speed > 0
WITH r, r.speed * (1000.0/3600.0) AS speed_ms
SET r.traveltime = r.sectionlength / speed_ms
RETURN count(*);

// Shortest Path Queries using different Shortest Path functions in Neo4j

// Cypher shortest path
MATCH sg=shortestPath((op1 WHERE op1.id = 'BEFBMZ')-[:SECTION*]-(op2 WHERE op2.id = 'DE000BL')) 
RETURN sg;

// APOC Dijkstra shortest path with weight sectionlength
MATCH (n:OperationalPoint), (m:OperationalPoint)
WHERE n.id = "BEFBMZ" and m.id = "DE000BL"
WITH n,m
CALL apoc.algo.dijkstra(n, m, 'SECTION', 'sectionlength') YIELD path, weight
RETURN path, weight;

// ******************************************************************************************
// Graph Data Science (GDS)
//
// Project a graph named 'OperationalPoints' Graph into memory. We only take the "OperationalPoint " 
// Node and the "SECTION" relationship
// ******************************************************************************************

CALL gds.graph.drop('OperationalPoints'); // optional, only if projection exists already
CALL gds.graph.project(
    'OperationalPoints',
    'OperationalPoint',
    {SECTION: {orientation: 'UNDIRECTED'}},
    {
        relationshipProperties: 'sectionlength'
  }
);

// Now we calculate the shortes path using GDS Dijkstra:
MATCH (source:OperationalPoint WHERE source.id = 'BEFBMZ'), (target:OperationalPoint WHERE target.id = 'DE000BL')
CALL gds.shortestPath.dijkstra.stream('OperationalPoints', {
    sourceNode: source,
    targetNode: target,
    relationshipWeightProperty: 'sectionlength'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN *;

// Now we use the Weakly Connected Components Algo
CALL gds.wcc.stream('OperationalPoints') YIELD nodeId, componentId
WITH collect(gds.util.asNode(nodeId).id) AS lista, componentId
RETURN lista,componentId order by size(lista) ASC;

// Matching a specific OperationalPoint  from the list above --> use the Neo4j browser output to check the network it is belonging to (see the README file for more information). You will figure out, that it is an isolated network of OperationalPoint s / stations / etc.:
MATCH (op:OperationalPoint) WHERE op.id='BEFBMZ' RETURN op;

// Use the betweenness centrality algo
CALL gds.betweenness.stream('OperationalPoints')
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).id AS id, score
ORDER BY score DESC;




///////////////////////////////////////////////////
// Fixed (in the sense of 'they run') up to here
/////////////////////////









// ===================================
//
// Some more special Queries
//
// ===================================
// Using to find the gap ...


///////////////////////////////////////////////
//
// Why are we using a path here?
//
//////////////////////////////
MATCH sg=(op1 WHERE op1.id STARTS WITH 'DE')-[:SECTION]-(op2 WHERE op2.id STARTS WITH 'EU')
MATCH (op3 WHERE op3.id STARTS WITH 'DK')
RETURN op2.id, op3.id, point.distance(op3.geolocation, op2.geolocation) AS distance
ORDER BY distance LIMIT 1;

// ===================================
// Setting a traveltime property on the SECTION relationship to calculate Shortest Path on time
//
// This query MUST run before using the "Speed vs. Time" Dashboard with NeoDash
// 
// Set new traveltime parameter in seconds for a particular section --> requires speed and 
// sectionlength properties set on this section!
// ===================================
MATCH (:OperationalPoint)-[r:SECTION]->(:OperationalPoint)
WHERE r.speed > 0
WITH r, r.speed * (1000.0/3600.0) AS speed_ms
SET r.traveltime = r.sectionlength / speed_ms
RETURN count(*);


// ====================
// Some more simple queries
// ====================

// Find Operation Points in Malmö
MATCH(op:OperationalPointName)
WHERE op.name CONTAINS 'Malmö'
RETURN op.name;

///////////////////////////////////////////////
//
// Rewrite to use Labels
//
//////////////////////////////

// Countries
MATCH (op:OperationalPoint)
RETURN DISTINCT substring(op.id,0,2) AS countries ORDER BY countries;



///////////////////////////////////////////////
//
// But this doesn't do that, as it gets ALL nodes, not just OPs
//
//////////////////////////////
// Find all different types of Operation Points / Labels
MATCH (n)
WITH DISTINCT labels(n) AS allOPs
UNWIND allOPs AS ops
RETURN DISTINCT ops;

///////////////////////////////////////////////
//
// But this doesn't do that, as it gets ALL nodes, not just OPs
//
//////////////////////////////
// Number of different Operation Points including POIs
MATCH (n)
WITH labels(n) AS allOPs
UNWIND allOPs AS ops
RETURN  ops, count(ops);


///////////////////////////////////////////////
//
// Number of different OP numbers, BY COUNTRY
//
//////////////////////////////
//
// Number of different OP Numbers
// 
MATCH (a:OperationalPoint)
WITH substring(a.id,0,2) AS country, collect(a.id) AS list
RETURN country, list[0];

//
// Cypher shortest path
//
///////////////////////////////////////////////
//
// Luckily this works, as there is only one type of rel between OperationalPoints, BUT
//   -[SECTION*]- should be -[:SECTION*]
// Also - no use of labels for nodes, so we're scanning the DB
// Point in case - Profiling:
//    'as is'           = 259,890 hits
//    Labels            = 54,878
//    :Section + Labels = 38,061
//
//////////////////////////////
MATCH p=shortestPath((op1:OperationalPoint WHERE op1.id = 'BEFBMZ')-[:SECTION*]-(op2:OperationalPoint WHERE op2.id = 'DE000BL')) RETURN p;
MATCH p=shortestPath((op1:OperationalPoint WHERE op1.id = 'FR0000002805')-[:SECTION*]-(op2:OperationalPoint WHERE op2.id = 'DE000BL')) RETURN p;
MATCH p=shortestPath((op1:OperationalPoint WHERE op1.id = 'ES60000')-[:SECTION*]-(op2:OperationalPoint WHERE op2.id = 'DE000BL')) RETURN p;

//
// APOC dijkstra shortes path
//

MATCH 
  (source:OperationalPoint WHERE source.id = 'BEFBMZ'), 
  (target:OperationalPoint WHERE target.id = 'DE000BL')
CALL apoc.algo.dijkstra(source, target, 'SECTION', 'sectionlength') 
YIELD path, weight
RETURN path, weight;

// Shortest path by distance (Rotterdam --> Den Bosch)
MATCH (n:OperationalPoint), (m:OperationalPoint)
WHERE n.id = "BEFBMZ" and m.id = "DE000BL"
WITH n,m
CALL apoc.algo.dijkstra(n, m, 'SECTION', 'sectionlength') YIELD path, weight
RETURN path, weight;


///////////////////////////////////
//
// Station doesn't have a Name property??
//
///////////////
// Shortest path by travel time (Rotterdam --> Den Bosch)
MATCH (n:OperationalPointName), (m:OperationalPointName)<-[]
WHERE n.name = "Rotterdam" and m.name CONTAINS "Hertogenbosch"
WITH n,m
CALL apoc.algo.dijkstra(n, m, 'ROUTE', 'travel_time_seconds') YIELD path, weight
RETURN path, weight;

// Business Like Queries



/// THEN WHY IS THIS HERE???
// =================================================================================
// This query is provided AS is. It propagades speed data to a country that does not 
// have speed data in the EU Railway Agency Database. DO NOT USE it for the graph loaded
// in this workshop!!!
// ================================================================================= 
CALL apoc.periodic.commit(
  "WITH $limit AS thelimit LIMIT $limit
   MATCH ()-[a:SECTION]-()-[b:SECTION]->()-[c:SECTION]-()
   WHERE b.sectionmaxspeed IS NULL
   WITH b, collect(DISTINCT a) + collect(DISTINCT c) AS sections
   UNWIND sections AS section
   WITH b, collect(section.sectionmaxspeed) AS speeds
   WHERE speeds <> []
   SET b.sectionmaxspeed = apoc.coll.avg(speeds)
   RETURN count(*)",{limit:10});

// mongo-init.js

rs.initiate({
  _id: "rs0",
  members: [{ _id: 0, host: "localhost:27017" }],
});

rs.status().members.forEach((member) => {
  print(`${member.name} - ${member.stateStr}`);
});

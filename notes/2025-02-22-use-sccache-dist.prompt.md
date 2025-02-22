Please modify existing setup so we leverage on sccache distributed mode so we run sccache scheduler and sccache builder inside one docker container and we configure localhost or other machines that compile Rust programs in a way that they leverage on this distributed setup and use and do compilation like delegate compilation to this docker container by IP port. Below you'll find some notes about this task that you may find helpful or not prepared by other assistant


### Main Objectives
- **Modify Current `sccache` Docker Setup**
  - Leverage `sccache` distributed mode compilation.
  - Ensure builds from various sources (local host, other Docker containers, other machines) compile in one designated container.

### Docker Container Setup
- **Combine Functions in One Docker Container**
  - Integrate both `sccache` Scheduler and `sccache` Builder into a single container.
  - Update Dockerfile to reflect this combined setup.

### Distributed Compilation
- **Point Compilation Building to Specified Container**
  - Allow endpoint specification by IP and port.
  - Facilitate builds from:
    - Local host.
    - Other Docker containers.
    - Other machines accessible over the network.

### System and Documentation Updates
- **Update Requirements Document**
  - Document combining `sccache` Scheduler and Builder in one Docker container.
  - Note the support for distributed setup across different systems.
  - Mark newly introduced requirements with a status checklist:
    - *[ ] Integrate Scheduler and Builder in one Docker container.*
    - *[ ] Enable distributed compilation via specified IP and port.*

### Documentation and Help Files
- **Revise Existing Documentation and Requirements document**
  - Update procedural documents to reflect the changes in Docker setup.
  - Add detailed instructions on configuring the local host for distributed compilation.

- **Add new sections as needed**
  - SCCache distributed setup explanation.
  - Configuration guidance for using combined `sccache` Scheduler and Builder container.

### Recommendations for Local Host Configuration
- **Configuration Script Recommendations**
  - Adapt recommendations based on updated script instructions.
  - Ensure instructions cover:
    - Network configuration for endpoint setup.
    - Prerequisites for enabling local and remote builds.

### Final Notes
- Ensure all documentation aligns with the new setup and offers clear implementation steps.
- Regularly review and test the setup to ensure conformity with the requirements and functional stability.

//! Git management engine and repository automation routines.

pub mod engine;

pub use engine::{
    GitCommitInfo, GitCommitResult, GitDiffResult, GitEngine, GitFileStatus, GitStatusResult,
};

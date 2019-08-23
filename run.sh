#!/bin/bash


#VARS:

REPO_USER=$WERCKER_CREATE_BRANCH_REPO_USER
REPO_NAME=$WERCKER_CREATE_BRANCH_REPO_NAME
REPO_PATH=$WERCKER_CACHE_DIR"/my_tmp/"$REPO_NAME
SOURCE_BRANCH=$WERCKER_CREATE_BRANCH_SOURCE_BRANCH
NEW_BRANCH=$WERCKER_CREATE_BRANCH_NEW_BRANCH
FORCE_BUILD_NUMBER=$WERCKER_DEPLOY_FORCE_BUILD_NUMBER
FORCE_CLONE=$WERCKER_CREATE_BRANCH_FORCE_CLONE

#END_VARS


#### functions


# clone or pull a repository
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: repo username
# ARG4: branch name
# ARG5: remove REPO_PATH
function clone_pull_repo (){
        local REPO=$1
        local REPO_PATH=$2
        local USER=$3
        local BRANCH=$4
        local DEL_REPO_PATH=$5


        if [[ ${DEL_REPO_PATH,,} == "yes" ]];then
                rm -rf $REPO_PATH
        fi
        #check if REPO_PATH exists
        if [ ! -d "$REPO_PATH" ]; then
                echo "Clone repository: $REPO"
                mkdir -p $REPO_PATH
                cd $REPO_PATH
                echo "git clone git@github.com:$USER/$REPO.git . >/dev/null"
                git clone git@github.com:$USER/$REPO.git . >/dev/null
                if [ $? -eq 0 ]; then
                        echo "Repository $REPO created"
                else
                        echo "Failed to create repository $REPO"
                        rm -rf $REPO_PATH
                        return 3
                fi
        fi
        echo "Pull repository: $REPO"
        cd $REPO_PATH
        git checkout $BRANCH
        if [ $? -eq 0 ]; then
                echo "Succesfully switched to branch $BRANCH"
                git pull 2>/dev/null
        else
                echo "Branch $BRANCH does not exists"
                return 3
        fi
        # prunes tracking branches not on the remote
        git remote prune origin | awk 'BEGIN{FS="origin/"};/pruned/{print $3}' | xargs -r git branch -D
        if [ $? -eq 0 ]; then
                echo "Repository $REPO pruned"
        else
                echo "Failed to prune repository $REPO"
                return 2
        fi
}

# Switch to a specific branch
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: branch name
#
function switch_branch(){
        local REPO=$1
        local REPO_PATH=$2
        local BRANCH=$3

        #check if REPO_PATH exists
        if [ -d "$REPO_PATH" ]; then
                echo "Switch to branch $BRANCH "
                cd $REPO_PATH
                #git pull >/dev/null
                git checkout $BRANCH >/dev/null
                if [ $? -eq 0 ]; then
                        echo "Succesfully switched to branch $BRANCH"
                else
                        echo "Branch $BRANCH does not exists"
                        return 3
                fi
        else
                echo "Please clone repository $REPO first"
                return 2
        fi


}


# Clone a branch from a specific branch
# Add a commit message
# push the new branch to the repository
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: source branch
# ARG4: to  branch
#
function clone_branch(){
        local REPO=$1
        local REPO_PATH=$2
        local FROM_BRANCH=$3
        local NEW_BRANCH=$4

        # switch to the soruce branch and update it
        switch_branch $REPO $REPO_PATH $FROM_BRANCH
        git checkout -b $NEW_BRANCH $FROM_BRANCH
        if [ $? -eq 0 ]; then
                echo "Succesfully created branch $NEW_BRANCH"
                #git commit --allow-empty -m "Deploy $FROM_BRANCH to $NEW_BRANCH"
                git push -f origin $NEW_BRANCH
                if [ $? -eq 0 ]; then
                        echo "Succesfully pushed branch $NEW_BRANCH"
                else
                        echo "Error during while pushing branch $NEW_BRANCH"
                        exit 2
                fi
        else
                echo "Errors during creating new branch $NEW_BRANCH"
                exit 3
        fi
}


function create_branch(){
        local REPO=$1
        local REPO_PATH=$2
        local USER=$3
        local FROM_BRANCH=$4
        local NEW_BRANCH=$5

        echo "clone_branch $REPO_NAME $REPO_PATH $SOURCE_BRANCH $NEW_BRANCH"
        clone_branch $REPO_NAME $REPO_PATH $SOURCE_BRANCH $NEW_BRANCH
        echo "get_build_number_commit_prefix_tag $REPO_NAME $REPO_PATH $REPO_USER $SOURCE_BRANCH"
        get_build_number_commit_prefix_tag $REPO_NAME $REPO_PATH $REPO_USER $SOURCE_BRANCH
        NEW_TAG=$NEW_BRANCH"+0"
        if [[ -n $FORCE_BUILD_NUMBER ]]; then
            echo "Force build number found: $FORCE_BUILD_NUMBER"
            NEW_TAG=$NEW_BRANCH"+"$FORCE_BUILD_NUMBER
        fi
        echo "NEW_TAG $NEW_TAG"
        echo "tag_commit_sha $REPO $REPO_PATH $USER $NEW_TAG $NEW_BRANCH $COMMIT_WITH_LATEST_TAG"
        tag_commit_sha $REPO_NAME $REPO_PATH $REPO_USER $NEW_TAG $NEW_BRANCH $LAST_COMMIT_SHA


}

# Tag commit. If the commit is not provided the last commit will be tagged
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: repo username
# ARG4: TAG
# ARG5: commit sha (if the commit sha is missing the last commit will be tagged)
#
function tag_commit_sha(){
        local REPO=$1
        local REPO_PATH=$2
        local USER=$3
        local NEW_TAG=$4
        local BRANCH=$5
        local COMMIT_SHA=$6

        if [ -d "$REPO_PATH" ]; then
                if [[ -z $COMMIT_SHA ]]; then
                        COMMIT_SHA=$(git rev-parse $BRANCH)
                fi
                echo "git tag $NEW_TAG $COMMIT_SHA"
                git tag $NEW_TAG $COMMIT_SHA
                git push origin $NEW_TAG

        else
                echo "Please clone repository $REPO first"
                return 2
        fi

}

# Get the latest build number and the latest commit
# ARG1: repo name
# ARG2: local PATH to store the repo
# ARG3: repo username
# ARG4: tag prefix (branch_name)
# return COMMIT_WITH_LATEST_TAG, LATEST_TAG (empty if the tag not found) and INCREASE_BUILD_NUMBER (do we need to increment BUILD_NUMBER)
function get_build_number_commit_prefix_tag(){
        local REPO=$1
        local REPO_PATH=$2
        local USER=$3
        local TAG_PREFIX=$4
        local FROM_BRANCH=$4

        echo "Tag Prefix: $TAG_PREFIX"

        switch_branch $REPO $REPO_PATH $FROM_BRANCH
        LATEST_BUILD_NUMBER=$(git tag -l $TAG_PREFIX\+* | cut -d\+ -f2| sort -rn|  head -n 1)
        if [[ -z $LATEST_BUILD_NUMBER ]];then
                LATEST_TAG=""
                COMMIT_WITH_LATEST_TAG=""
        else
                LATEST_TAG=$TAG_PREFIX"+"$LATEST_BUILD_NUMBER
                COMMIT_WITH_LATEST_TAG=$(git rev-list -1 $LATEST_TAG)
                echo "commit with latest tag: $COMMIT_WITH_LATEST_TAG"
        fi

}



#### end functions


if [[ -z $REPO_NAME ]];then
    echo "Please specify a repository"
    exit 1
fi

if [[ -z $REPO_USER ]];then
    echo "Please specify use repository"
    exit 1
fi

if [[ -z $SOURCE_BRANCH ]];then
    echo "Please specify source branch"
    exit 1
fi

if [[ -z $NEW_BRANCH ]];then
    echo "Please specify the new branch"
    exit 1
fi


#******** create branch ********
# clone or create repository
echo "clone_pull_repo $REPO_NAME $REPO_PATH $REPO_USER $SOURCE_BRANCH $FORCE_CLONE"
clone_pull_repo $REPO_NAME $REPO_PATH $REPO_USER $SOURCE_BRANCH $FORCE_CLONE
echo "create_branch $REPO_NAME $REPO_PATH $REPO_USERUSER $SOURCE_BRANCH $NEW_BRANCH"
create_branch $REPO_NAME $REPO_PATH $REPO_USER $SOURCE_BRANCH $NEW_BRANCH


# EKS-n-CICD
(notes from aws-eks-kubernetes-masterclass from Udemy)
# DevOps with AWS Developer Tools on AWS EKS

## Step-01: DevOps
-  Spin up EKS cluster using eksctl cli
-  AWS Tools that help us to implement DevOps.
    - AWS CodeCommit
    - AWS CodeBuild
    - AWS CodePipeline
```
eksctl create cluster --name=eksdemo1 --region=us-east-1 --zones=us-east-1a,us-east-1b   --without-nodegroup
eksctl utils associate-iam-oidc-provider --region us-east-1 --cluster eksdemo1 --approve
eksctl create nodegroup --cluster=eksdemo1 --region=us-east-1 --name=eksdemo1-ng-private1 --node-type=t3.medium --nodes-min=2 --nodes-max=4 --node-volume-size=20 --ssh-access --ssh-public-key=kube-demo --managed --asg-access --external-dns-access --full-ecr-access --appmesh-access --alb-ingress-access --node-private-networking  
kube-demo keypair
```
For both Public Subnets, add the tag as `kubernetes.io/cluster/eksdemo1 =  shared` 
Add all traffic to worker nodes 

## Step-02: Pre-requisite check
- We are going to deploy a application which will also have a `ALB Ingress Service` 
- Which means we should have both related pods running in our cluster. 

Ingress:
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/master/docs/examples/rbac-role.yaml
kubectl get sa -n kube-system
aws iam create-policy --policy-name ALBIngressControllerIAMPolicy --policy-document https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/master/docs/examples/iam-policy.json

# Replaced region, name, cluster and policy arn (Policy arn we took note in step-03)
eksctl create iamserviceaccount --region us-east-1 --name alb-ingress-controller --namespace kube-system --cluster eksdemo1 --attach-policy-arn arn:aws:iam::080400906742:policy/ALBIngressControllerIAMPolicy --override-existing-serviceaccounts --approve

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/master/docs/examples/alb-ingress-controller.yaml

kubectl get deploy -n kube-system

kubectl edit deployment.apps/alb-ingress-controller -n kube-system
- --ingress-class=alb
- --cluster-name=eksdemo1

kubectl get pods -n kube-system

```

## Step-03: Create ECR Repository for our Application Docker Images

## Step-04: Create CodeCommit Repository
```
git status
git add .
git commit -am "1 Added all files"
git push
git status
```
- Verify the same on CodeCommit Repository in AWS Management console.

## Step-05: Create STS Assume IAM Role for CodeBuild to interact with AWS EKS
- In an AWS CodePipeline, we are going to use AWS CodeBuild to deploy changes to our Kubernetes manifests. 
- This requires an AWS IAM role capable of interacting with the EKS cluster.
- In this step, we are going to create an IAM role and add an inline policy `EKS:Describe` that we will use in the CodeBuild stage to interact with the EKS cluster via kubectl.
```
# Export your Account ID
export ACCOUNT_ID=180789647333

# Set Trust Policy
TRUST="{ \"Version\": \"2012-10-17\", \"Statement\": [ { \"Effect\": \"Allow\", \"Principal\": { \"AWS\": \"arn:aws:iam::${ACCOUNT_ID}:root\" }, \"Action\": \"sts:AssumeRole\" } ] }"

# Verify inside Trust policy, your account id got replacd
echo $TRUST

# Create IAM Role for CodeBuild to Interact with EKS
aws iam create-role --role-name EksCodeBuildKubectlRole --assume-role-policy-document "$TRUST" --output text --query 'Role.Arn'

# Define Inline Policy with eks Describe permission in a file iam-eks-describe-policy
echo '{ "Version": "2012-10-17", "Statement": [ { "Effect": "Allow", "Action": "eks:Describe*", "Resource": "*" } ] }' > /tmp/iam-eks-describe-policy

# Associate Inline Policy to our newly created IAM Role
aws iam put-role-policy --role-name EksCodeBuildKubectlRole --policy-name eks-describe --policy-document file:///tmp/iam-eks-describe-policy

# Verify the same on Management Console
```

## Step-06: Update EKS Cluster aws-auth ConfigMap with new role created in previous step
- We are going to add the role to the `aws-auth ConfigMap` for the EKS cluster.
- Once the `EKS aws-auth ConfigMap` includes this new role, kubectl in the CodeBuild stage of the pipeline will be able to interact with the EKS cluster via the IAM role.
```
# Verify what is present in aws-auth configmap before change
kubectl get configmap aws-auth -o yaml -n kube-system

# Export your Account ID
export ACCOUNT_ID=180789647333

# Set ROLE value
ROLE="    - rolearn: arn:aws:iam::$ACCOUNT_ID:role/EksCodeBuildKubectlRole\n      username: build\n      groups:\n        - system:masters"

# Get current aws-auth configMap data and attach new role info to it
kubectl get -n kube-system configmap/aws-auth -o yaml | awk "/mapRoles: \|/{print;print \"$ROLE\";next}1" > /tmp/aws-auth-patch.yml

# Patch the aws-auth configmap with new role
kubectl patch configmap/aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yml)"

# Verify what is updated in aws-auth configmap after change
kubectl get configmap aws-auth -o yaml -n kube-system
```

## Step-07: Review the buildspec.yml for CodeBuild & Environment Variables

### Code Build Introduction
- Get a high level overview about CodeBuild Service

### Environment Variables for CodeBuild
```
REPOSITORY_URI = 180789647333.dkr.ecr.us-east-1.amazonaws.com/eks-devops-nginx
EKS_KUBECTL_ROLE_ARN = arn:aws:iam::180789647333:role/EksCodeBuildKubectlRole
EKS_CLUSTER_NAME = eksdemo1
```

## Step-08: Create CodePipeline

## Step-09: Updae CodeBuild Role to have access to ECR full access   
- First pipeline run will fail as CodeBuild not able to upload or push newly created Docker Image to ECR Repostory
- Update the CodeBuild Role to have access to ECR to upload images built by codeBuild. 
  - Role Name: codebuild-eks-devops-cb-for-pipe-service-role
  - Policy Name: AmazonEC2ContainerRegistryFullAccess
- Make changes to index.html (Update as V2),  locally and push change to CodeCommit

## Step-10: Update CodeBuild Role to have access to STS Assume Role we have created using STS Assume Role Policy
- Build should be failed due to CodeBuild dont have access to perform updates in EKS Cluster.
- It even cannot assume the STS Assume role whatever we created. 
- Create STS Assume Policy and Associate that to CodeBuild Role `codebuild-eks-devops-cb-for-pipe-service-role`

### Create STS Assume Role Policy
- Go to Services IAM -> Policies -> Create Policy
- In **Visual Editor Tab**
- Service: STS
- Actions: Under Write - Select `AssumeRole`
- Resources: Specific
  - Add ARN
  - Specify ARN for Role: arn:aws:iam::180789647333:role/EksCodeBuildKubectlRole
  - Click Add
```
# For Role ARN, replace your account id here, refer step-07 environment variable EKS_KUBECTL_ROLE_ARN for more details
arn:aws:iam::<your-account-id>:role/EksCodeBuildKubectlRole
```
- Click on Review Policy  
- Name: eks-codebuild-sts-assume-role
- Description: CodeBuild to interact with EKS cluster to perform changes
- Click on **Create Policy**

### Associate Policy to CodeBuild Role
- Role Name: codebuild-eks-devops-cb-for-pipe-service-role
- Policy to be associated:  `eks-codebuild-sts-assume-role`
  
```  
kubectl exec -it <pod> /bin/sh
```

For kubectl in AWS cloud shell:
  
In AWS Cloud Shell:

sudo -i
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/sbin/kubectl
kubectl version --client

exit
copy .kube config file 

